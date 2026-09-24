#!/usr/bin/env python3
"""Speak the final answer of each Claude Code turn aloud.

Registered in ~/.claude/settings.json on Stop. Off by default; the
/tts-toggle slash command (~/.claude/skills/tts-toggle/) turns it on per
session; /tts-voice (~/.claude/skills/tts-voice/) picks the voice:

    voice_reply.py hook       read one hook event (JSON) from stdin
    voice_reply.py session [SESSION_ID] [on|off|toggle]
                              enable/disable speaking for a session (default:
                              $CLAUDE_CODE_SESSION_ID, toggle)
    voice_reply.py voice [SPEC] [--speed X] [--reset]
                              show or set the Kokoro voice (saved in SETTINGS)
    voice_reply.py say TEXT   speak TEXT as if it were a reply (testing)
    voice_reply.py stop       silence now: drop queued speech, stop playback
    voice_reply.py status     show daemon/queue/backend state
    voice_reply.py daemon     the speaker process (started by `hook`)

How it fits together:

* The Stop hook does nothing unless the session has been switched on (a
  flag file per session id in RUN_DIR/enabled; tmpfs, so a reboot resets
  everything to off). It takes `last_assistant_message` (the turn's final answer;
  narration between tool calls is not spoken), appends it to a global queue
  and makes sure the daemon is running. It never speaks itself.
* A single daemon (one per user, so two sessions never talk over each
  other) runs three stages concurrently:
  1. rewrite: Haiku (via `claude -p`, hooks off) turns the markdown reply
     into plain spoken paragraphs, streamed, so the first paragraph moves on
     before the rest is written. Plain short prose skips this; if Haiku
     fails, a regex conversion (MessageReader) is used instead.
  2. synthesise: each paragraph is one request to Kokoro-82M on legion's GPU
     (see kokoro_server.py next to this file), ~80x faster than real time,
     so synthesis never holds up playback.
  3. play: one persistent `pacat` stream.
* If legion fails, the paragraph is spoken with local Piper and legion is
  skipped for LEGION_RETRY_SECS.
"""
import fcntl
import json
import os
import re
import select
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

# Voice and speed live in SETTINGS (set with `voice_reply.py voice`, i.e.
# /tts-voice) and are read for every paragraph, so a change applies at once.
# A voice is a name, an even blend "a,b" or a weighted mix "a:0.4,b:0.6".
DEFAULT_VOICE = "af_bella"
DEFAULT_SPEED = 1.0
SETTINGS = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "claude-voice/settings.json"
LEGION_HOST = "legion"
LEGION_PORT = 8767
LEGION_RETRY_SECS = 60
SSH_OPTS = [
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=3",
    "-o", "ControlMaster=auto",
    "-o", "ControlPersist=10m",
    "-o", "ControlPath=~/.ssh/cm-voice-%r@%h:%p",
]
PIPER_BIN = Path.home() / ".local/share/piper/bin/piper"
PIPER_VOICE = Path.home() / ".local/share/piper/voices/en_US-lessac-medium.onnx"
PIPER_RATE = 22_050

# The real binary, not the account-toggling wrapper that `claude` on PATH is.
CLAUDE_BIN = "/opt/claude-code/bin/claude"
REWRITE_MODEL = "haiku"
REWRITE_FIRST_TIMEOUT = 25
REWRITE_TOTAL_TIMEOUT = 120
REWRITE_PROMPT = """\
You turn a coding assistant's chat reply into a script that a text-to-speech \
voice reads aloud to the user. The reply is inside <reply> tags. Never answer \
or comment on it; output only the script.

Keep the conversion minimal: same meaning, same order, same first-person voice \
talking to the user. Do not summarise ordinary prose, and never add facts, \
units or details that are not in the reply.

Make it speakable:
- No markdown, bullets, headings, emoji or symbols. Turn lists into sentences.
- Never read out code, commands, diffs, tables, logs or JSON. Replace each with \
one short sentence saying what it is or shows.
- Paths and URLs: say only the file or site name, as a person would ("voice \
reply dot py"). Drop line numbers, hashes and IDs unless they matter.
- Write numbers, units, versions and ranges as they are spoken ("about 1.2 \
seconds", "5 to 10").
- Expand abbreviations a listener would stumble on; keep common ones like API \
or GPU.

Format: plain paragraphs of one to three sentences, each under about 200 \
characters, separated by blank lines."""

RATE = 24_000  # playback rate (Kokoro's native rate; Piper is resampled)
GAP_SECS = 0.2  # silence between paragraphs
FIRST_BYTE_TIMEOUT = 10
TOTAL_TIMEOUT = 30
IDLE_EXIT_SECS = 30

RUN_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/claude-voice-{os.getuid()}") / "claude-voice"
QUEUE = RUN_DIR / "queue.jsonl"
QUEUE_LOCK = RUN_DIR / "queue.lock"
DAEMON_LOCK = RUN_DIR / "daemon.lock"
DAEMON_PID = RUN_DIR / "daemon.pid"
LEGION_DOWN = RUN_DIR / "legion-down-until"
LOG = RUN_DIR / "voice.log"
ENABLED = RUN_DIR / "enabled"  # one empty file per session with voice switched on


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} [{os.getpid()}] {msg}\n")
    except OSError:
        pass


class Locked:
    """Exclusive flock on a lock file for the duration of a with-block."""

    def __init__(self, path, blocking=True):
        self.path, self.blocking, self.fd = path, blocking, None

    def __enter__(self):
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | (0 if self.blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            os.close(self.fd)
            self.fd = None
        return self.fd is not None

    def __exit__(self, *exc):
        if self.fd is not None:
            os.close(self.fd)


# ---------------------------------------------------------------- text


ABBREVIATIONS = {"e.g.": "for example", "i.e.": "that is", "etc.": "etcetera", "vs.": "versus"}


def speakable_inline(text):
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)  # images
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)  # links
    text = re.sub(r"<?https?://[^\s>)]+>?", "a link", text)
    text = text.replace("`", "")
    # Paths: speak the file name only (plus the line number of path:line).
    text = re.sub(
        r"(?<![\w.])(?:~|\.{1,2})?/?(?:[\w.@+-]+/){2,}([\w.@+-]+)(?::(\d+))?",
        lambda m: m.group(1) + (f" line {m.group(2)}" if m.group(2) else ""),
        text,
    )
    text = re.sub(r"(?<![\w.])~/([\w.@+-]+)", r"\1", text)
    text = re.sub(r"(\*\*|__)(.+?)\1", r"\2", text)  # bold
    text = re.sub(r"(?<!\w)[*_]([^*_\n]+)[*_](?!\w)", r"\1", text)  # italics
    text = re.sub(r"(?<=\w)_(?=\w)", " ", text)  # snake_case
    for abbr, spoken in ABBREVIATIONS.items():
        text = text.replace(abbr, spoken)
    text = re.sub(r"(?<=\d)\s*\u2013\s*(?=\d)", " to ", text)  # 5-10 written with an en dash
    text = re.sub(r"(?<=\w)-{2,3}(?=\w)|\s+-{2,3}\s+|\s*[\u2013\u2014]\s*", ", ", text)  # dashes
    text = re.sub(r"\s*(->|=>|\u2192)\s*", " to ", text)
    text = re.sub(r"~(?=\d)", "about ", text)
    text = text.replace("&", " and ").replace("|", ", ").replace("*", "")
    return re.sub(r"\s+", " ", text).strip()


class MessageReader:
    """Regex markdown-to-speech, line by line: the fallback when Haiku is
    unavailable, and a safety pass over Haiku's own output.

    Fenced code blocks are summarised; tables are announced once and
    skipped; everything else is one segment per line (a paragraph, list item
    or heading)."""

    def __init__(self):
        self.carry = ""
        self.fence = None  # [marker, lang, line_count] while inside one
        self.in_table = False

    def feed(self, text, final=False):
        lines = (self.carry + text).split("\n")
        self.carry = "" if final else lines.pop()
        out = [s for line in lines if (s := self._line(line))]
        if final and self.fence:
            out.append(self._code_summary())
            self.fence = None
        return out

    def _code_summary(self):
        _, lang, n = self.fence
        return f"Skipping a {n} line {lang + ' ' if lang else ''}code block."

    def _line(self, line):
        s = line.strip()
        if self.fence:
            if s.startswith(self.fence[0]):
                summary = self._code_summary()
                self.fence = None
                return summary
            self.fence[2] += 1
            return None
        if m := re.match(r"(`{3,}|~{3,})\s*([\w+#.-]*)", s):
            self.fence = [m.group(1), m.group(2), 0]
            return None
        if s.startswith("|"):
            was_table, self.in_table = self.in_table, True
            return None if was_table else "Skipping a table."
        self.in_table = False
        if not s or re.fullmatch(r"([-*_]\s*){3,}", s):
            return None
        s = re.sub(r"^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?)+", "", s)
        s = speakable_inline(s)
        if not re.search(r"\w", s):
            return None
        if s[-1] not in ".!?:;,":
            s += "."
        return s


def needs_rewrite(text):
    """Plain prose without markdown, code, paths or numbers reads fine as
    is; skipping Haiku for it saves a couple of seconds."""
    return bool(re.search(r"[`*#|\[\]_<>~/\\{}=]|\d|^\s*[-+]\s", text, re.M))


def rewrite_for_speech(text):
    """Yield spoken paragraphs of `text` from Haiku, as they stream in."""
    proc = subprocess.Popen(
        [CLAUDE_BIN, "-p", "--model", REWRITE_MODEL, "--no-session-persistence",
         "--settings", json.dumps({"disableAllHooks": True, "alwaysThinkingEnabled": False}),
         "--setting-sources", "", "--strict-mcp-config", "--tools", "",
         "--system-prompt", REWRITE_PROMPT,
         "--output-format", "stream-json", "--include-partial-messages", "--verbose"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=RUN_DIR,
        # CLAUDE_VOICE_CHILD: belt and braces against speaking our own call.
        env={**os.environ, "CLAUDE_VOICE_CHILD": "1", "MAX_THINKING_TOKENS": "0"},
    )
    proc.stdin.write(f"<reply>\n{text}\n</reply>\n".encode())
    proc.stdin.close()
    start, got_text, buf, pending = time.time(), False, "", b""
    try:
        while True:
            elapsed = time.time() - start
            if elapsed > (REWRITE_TOTAL_TIMEOUT if got_text else REWRITE_FIRST_TIMEOUT):
                raise TimeoutError(f"rewrite timed out after {elapsed:.0f}s")
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if not ready:
                continue
            data = os.read(proc.stdout.fileno(), 65536)
            if not data:
                break
            pending += data
            *lines, pending = pending.split(b"\n")
            for raw in lines:
                try:
                    event = json.loads(raw)
                except ValueError:
                    continue
                if event.get("type") == "result" and event.get("is_error"):
                    raise RuntimeError(f"rewrite failed: {str(event.get('result'))[:200]}")
                delta = (event.get("event") or {}).get("delta") or {}
                if event.get("type") == "stream_event" and delta.get("type") == "text_delta":
                    got_text = True
                    buf += delta["text"]
                    *done, buf = buf.split("\n")
                    yield from (p.strip() for p in done if p.strip())
        if not got_text:
            raise RuntimeError("rewrite produced no text")
        if buf.strip():
            yield buf.strip()
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()


# ---------------------------------------------------------------- hook side


def enqueue(text):
    with Locked(QUEUE_LOCK):
        with open(QUEUE, "a") as f:
            f.write(json.dumps({"text": text}) + "\n")
    ensure_daemon()


def ensure_daemon():
    # Must run after the queue write: the daemon only exits after seeing an
    # empty queue while holding QUEUE_LOCK, and releases DAEMON_LOCK before
    # QUEUE_LOCK, so either it sees our entry or we see the lock free.
    with Locked(DAEMON_LOCK, blocking=False) as free:
        if not free:
            return
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "daemon"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,  # outlive the hook; Claude Code kills hooks on timeout
    )


def cmd_hook():
    if os.environ.get("CLAUDE_VOICE_CHILD"):
        return
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not (ENABLED / session_file(event.get("session_id", ""))).exists():
        return
    text = event.get("last_assistant_message") or ""
    if event.get("hook_event_name") == "Stop" and text.strip():
        enqueue(text)


def session_file(session_id):
    return re.sub(r"[^\w-]", "_", session_id) or "unknown"


def cmd_session(args):
    actions = [a for a in args if a in ("on", "off", "toggle")]
    ids = [a for a in args if a not in actions and a.strip()]
    session_id = ids[0] if ids else os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        sys.exit("no session id given and CLAUDE_CODE_SESSION_ID is not set")
    flag = ENABLED / session_file(session_id)
    action = actions[0] if actions else "toggle"
    on = not flag.exists() if action == "toggle" else action == "on"
    if on:
        flag.touch()
    else:
        flag.unlink(missing_ok=True)
        cmd_stop()  # don't keep talking after being switched off
    print(f"Voice replies {'on' if on else 'off'} for this session.")


# ---------------------------------------------------------------- daemon side


def pop_queue():
    with Locked(QUEUE_LOCK):
        try:
            lines = QUEUE.read_text().splitlines()
        except OSError:
            return []
        QUEUE.write_text("")
    return [json.loads(line) for line in lines if line.strip()]


def legion_down():
    try:
        return time.time() < float(LEGION_DOWN.read_text())
    except (OSError, ValueError):
        return False


def load_settings():
    try:
        saved = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        saved = {}
    return {"voice": saved.get("voice") or DEFAULT_VOICE, "speed": float(saved.get("speed") or DEFAULT_SPEED)}


def synth_kokoro(text, settings=None):
    payload = json.dumps({"text": text, **(settings or load_settings())}).encode()
    proc = subprocess.Popen(
        ["ssh", *SSH_OPTS, LEGION_HOST,
         f"curl -sfN --max-time {TOTAL_TIMEOUT} -X POST http://127.0.0.1:{LEGION_PORT}/tts/stream "
         "-H 'Content-Type: application/json' --data-binary @-"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    proc.stdin.write(payload)
    proc.stdin.close()
    chunks, start = [], time.time()
    try:
        while True:
            elapsed = time.time() - start
            if elapsed > (TOTAL_TIMEOUT if chunks else FIRST_BYTE_TIMEOUT):
                raise TimeoutError(f"no audio after {elapsed:.0f}s")
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if ready:
                data = os.read(proc.stdout.fileno(), 65536)
                if not data:
                    break
                chunks.append(data)
        if proc.wait(timeout=5) != 0:
            raise RuntimeError(f"ssh/curl exit {proc.returncode}: {proc.stderr.read().decode(errors='replace').strip()[:200]}")
    finally:
        if proc.poll() is None:
            proc.kill()
    pcm = b"".join(chunks)
    if len(pcm) < RATE // 10:
        raise RuntimeError("empty audio")
    return pcm


def synth_piper(text):
    import numpy as np

    raw = subprocess.run(
        [str(PIPER_BIN), "-m", str(PIPER_VOICE), "--output_raw"],
        input=text.encode(), capture_output=True, check=True,
    ).stdout
    x = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
    n = int(len(x) * RATE / PIPER_RATE)
    y = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return y.astype(np.int16).tobytes()


def synthesize(text):
    if not legion_down():
        t0 = time.time()
        try:
            pcm = synth_kokoro(text)
            log(f"kokoro {len(text)}ch gen={time.time() - t0:.1f}s audio={len(pcm) / 2 / RATE:.1f}s")
            return pcm
        except Exception as e:  # noqa: BLE001 -- any failure means: use Piper
            log(f"kokoro failed ({e}); piper for {LEGION_RETRY_SECS}s")
            LEGION_DOWN.write_text(str(time.time() + LEGION_RETRY_SECS))
    try:
        pcm = synth_piper(text)
        log(f"piper {len(text)}ch audio={len(pcm) / 2 / RATE:.1f}s")
        return pcm
    except Exception as e:  # noqa: BLE001
        log(f"piper failed: {e}")
        return b""


class Speaker:
    """Rewrite, synthesis and playback stages, each on its own thread, joined
    by lists guarded by one condition variable."""

    def __init__(self, lock_fd):
        self.lock_fd = lock_fd
        self.cond = threading.Condition()
        self.rewriting = False
        self.paragraphs = []  # waiting for synthesis, one request each
        self.synthesizing = False
        self.audio = []  # synthesized chunks waiting to play
        self.playing = False
        self.play_end = 0.0  # when the audio handed to pacat finishes playing
        self.pacat = None

    def run(self):
        threading.Thread(target=self._rewrite_loop, daemon=True).start()
        threading.Thread(target=self._play_loop, daemon=True).start()
        idle_since = time.time()
        while True:
            with self.cond:
                self.synthesizing = bool(self.paragraphs)
                if self.synthesizing:
                    text = self.paragraphs.pop(0)
                elif self.rewriting or self.audio or self.playing:
                    idle_since = time.time()
                elif time.time() - idle_since > IDLE_EXIT_SECS and self._try_exit():
                    return
                if not self.synthesizing:
                    self.cond.wait(0.5)
                    continue
            pcm = synthesize(text)
            with self.cond:
                if pcm:
                    self.audio.append(pcm + bytes(int(GAP_SECS * RATE) * 2))
                self.cond.notify_all()
            idle_since = time.time()

    def _try_exit(self):
        """Exit if the queue is empty. Caller holds self.cond, which the
        rewrite thread also takes before popping the queue."""
        with Locked(QUEUE_LOCK):
            if QUEUE.exists() and QUEUE.stat().st_size:
                return False
            if self.pacat:
                self.pacat.stdin.close()
                self.pacat.wait()
            DAEMON_PID.unlink(missing_ok=True)
            os.close(self.lock_fd)  # release DAEMON_LOCK before QUEUE_LOCK
            return True

    def _add_paragraphs(self, paragraphs):
        with self.cond:
            self.paragraphs += paragraphs
            self.cond.notify_all()

    def _rewrite_loop(self):
        while True:
            with self.cond:
                entries = pop_queue()
                self.rewriting = bool(entries)
            if not entries:
                time.sleep(0.2)
                continue
            for entry in entries:
                self._rewrite(entry["text"])
            with self.cond:
                self.rewriting = False
                self.cond.notify_all()

    def _rewrite(self, text):
        if not needs_rewrite(text):
            self._add_paragraphs(MessageReader().feed(text, final=True))
            return
        t0, first, n_out, cleanup = time.time(), None, 0, MessageReader()
        try:
            for paragraph in rewrite_for_speech(text):
                first = first or time.time() - t0
                spoken = cleanup.feed(paragraph + "\n")  # strips any stray markdown
                n_out += sum(map(len, spoken))
                self._add_paragraphs(spoken)
            log(f"rewrite {len(text)}ch -> {n_out}ch, first paragraph {first:.1f}s, done {time.time() - t0:.1f}s")
        except Exception as e:  # noqa: BLE001 -- fall back to the regex conversion
            log(f"rewrite failed ({e}); regex conversion")
            if first is None:
                self._add_paragraphs(MessageReader().feed(text, final=True))

    def _play_loop(self):
        while True:
            with self.cond:
                while not self.audio:
                    self.playing = False
                    self.cond.wait()
                pcm = self.audio.pop(0)
                self.playing = True
            duration = len(pcm) / 2 / RATE
            now = time.time()
            if 0.3 < now - self.play_end < IDLE_EXIT_SECS:
                log(f"gap {now - self.play_end:.1f}s waiting for synthesis")
            self.play_end = max(now, self.play_end) + duration
            if self.pacat is None or self.pacat.poll() is not None:
                self.pacat = subprocess.Popen(
                    ["pacat", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
                     "--client-name=Claude Code", "--stream-name=voice reply"],
                    stdin=subprocess.PIPE, stderr=subprocess.DEVNULL,
                )
            try:
                self.pacat.stdin.write(pcm)
                self.pacat.stdin.flush()
            except BrokenPipeError:
                self.pacat = None
                continue
            # pacat accepts audio faster than it plays; wait out the chunk so
            # `playing` (and hence idle detection) is honest.
            time.sleep(max(0.0, self.play_end - time.time() - 0.3))


def cmd_daemon():
    lock_fd = os.open(DAEMON_LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # another daemon won the race
    if LOG.exists() and LOG.stat().st_size > 1_000_000:
        LOG.write_text("")
    DAEMON_PID.write_text(str(os.getpid()))
    speaker = Speaker(lock_fd)

    def on_term(*_):
        if speaker.pacat and speaker.pacat.poll() is None:
            speaker.pacat.kill()
        DAEMON_PID.unlink(missing_ok=True)
        os._exit(0)

    signal.signal(signal.SIGTERM, on_term)
    log("daemon start")
    speaker.run()
    log("daemon idle exit")


# ---------------------------------------------------------------- CLI


def cmd_stop():
    with Locked(QUEUE_LOCK):
        QUEUE.write_text("")
    try:
        os.kill(int(DAEMON_PID.read_text()), signal.SIGTERM)
    except (OSError, ValueError):
        pass


def cmd_status():
    try:
        pid = int(DAEMON_PID.read_text())
        os.kill(pid, 0)
        print(f"daemon: running (pid {pid})")
    except (OSError, ValueError):
        print("daemon: not running")
    try:
        print(f"queued replies: {len(QUEUE.read_text().splitlines())}")
    except OSError:
        print("queued replies: 0")
    print("legion: " + ("skipped after a failure" if legion_down() else "in use"))
    sessions = sorted(p.name for p in ENABLED.iterdir()) if ENABLED.exists() else []
    print(f"voice on for sessions: {', '.join(sessions) or 'none'}")
    if LOG.exists():
        print("recent log:")
        print("".join(LOG.read_text().splitlines(keepends=True)[-8:]), end="")


def cmd_voice(args):
    settings = load_settings()
    if "--reset" in args:
        SETTINGS.unlink(missing_ok=True)
        settings = load_settings()
        print(f"Voice reset to {settings['voice']} at speed {settings['speed']:g}.")
        return
    speed = None
    if "--speed" in args:
        i = args.index("--speed")
        try:
            speed = float(args[i + 1])
        except (IndexError, ValueError):
            sys.exit("--speed needs a number, e.g. --speed 1.1")
        if not 0.5 <= speed <= 2.0:
            sys.exit("speed must be between 0.5 and 2.0")
        del args[i:i + 2]
    spec = "".join(args).replace(" ", "")
    if not spec and speed is None:
        print(f"Current voice: {settings['voice']} at speed {settings['speed']:g}.")
        return
    if spec:
        if not re.fullmatch(r"[a-z]{2}_[a-z]+(:[0-9.]+)?(,[a-z]{2}_[a-z]+(:[0-9.]+)?)*", spec):
            sys.exit(f"not a voice spec: {spec!r} (want name, a,b or a:0.4,b:0.6)")
        if ":" in spec and not all(":" in part for part in spec.split(",")):
            sys.exit("in a weighted mix, give every voice a weight")
        settings["voice"] = spec
    if speed is not None:
        settings["speed"] = speed
    # Check with Kokoro that every voice exists (unknown names make it fail).
    try:
        synth_kokoro("Check.", settings)
        checked = ""
    except Exception as e:  # noqa: BLE001
        # The server fails mid-stream on a bad name: curl exits 18 (partial
        # body) or nothing comes back. ssh/connect failures are other codes.
        if re.search(r"exit (18|22)\b|empty audio", str(e)):
            sys.exit(f"Kokoro rejected {settings['voice']!r}; check the voice names")
        checked = f" (not checked: legion unreachable: {e})"
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(settings) + "\n")
    print(f"Voice set to {settings['voice']} at speed {settings['speed']:g}{checked}.")


def main():
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    ENABLED.mkdir(exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "hook"
    if cmd == "hook":
        cmd_hook()
    elif cmd == "daemon":
        cmd_daemon()
    elif cmd == "session":
        cmd_session(sys.argv[2:])
    elif cmd == "voice":
        cmd_voice(sys.argv[2:])
    elif cmd == "say":
        enqueue(" ".join(sys.argv[2:]) or sys.stdin.read())
    elif cmd == "stop":
        cmd_stop()
    elif cmd == "status":
        cmd_status()
    else:
        sys.exit(f"usage: {sys.argv[0]} [hook|session [ID] [on|off|toggle]|voice [SPEC] [--speed X] [--reset]|say TEXT|stop|status|daemon]")


if __name__ == "__main__":
    main()
