"""Kokoro TTS server for Claude Code voice replies.

Client: ~/.claude/scripts/voice-reply/voice_reply.py on the workstation
(reaches this over `ssh legion curl ...`; the server only listens on
localhost). Runs in ~/kokoro-env on legion as the systemd user service
kokoro-tts.service.

Endpoints:
  GET  /health       -> {"status": "ok", "voices": [...], "gpu_mb": {...}}
  POST /tts/stream   -> raw s16le mono 24 kHz PCM, streamed per sentence
  POST /tts          -> the same audio as a complete WAV file

`voice` is a voice name, or a weighted mix "af_nicole:0.4,ff_siwis:0.6"
(Kokoro's own "a,b" syntax only does equal weights).

Kokoro-82M replaced Orpheus (3B, sampled token by token): Kokoro's voice is
a fixed style vector, so it sounds the same in every chunk, and on the RTX
3070 it synthesises ~80x faster than real time (Orpheus managed ~1x).

GPU memory: the 8 GB card is shared with Marker (the narrator skill's PDF
conversion, ~2.6 GB), so PyTorch's allocator is capped at MAX_GPU_GB and
its cache is emptied after every request. Inference peaks at ~1.1 GB
allocated (long inputs are split into bounded chunks); with the CUDA context
the process stays under ~2 GB, ~0.8 GB when idle. Without this it kept
~3.2 GB cached.
"""
import io
import os

os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")  # before torch loads
import threading
import wave

import numpy as np
import torch
from fastapi import FastAPI
from fastapi.responses import Response, StreamingResponse
from kokoro import KPipeline
from pydantic import BaseModel

SAMPLE_RATE = 24_000
MAX_GPU_GB = float(os.environ.get("KOKORO_MAX_GPU_GB", "1.5"))
# American (a*) and British (b*) English voices; af_heart rates best.
VOICES = [
    "af_heart", "af_bella", "af_nicole", "af_aoede", "af_kore", "af_sarah", "af_nova", "af_sky",
    "af_alloy", "af_jessica", "af_river", "am_michael", "am_fenrir", "am_puck", "am_echo",
    "am_eric", "am_liam", "am_onyx", "am_adam", "bf_emma", "bf_isabella", "bf_alice",
    "bf_lily", "bm_george", "bm_fable", "bm_lewis", "bm_daniel",
]

torch.cuda.set_per_process_memory_fraction(
    min(1.0, MAX_GPU_GB * 2**30 / torch.cuda.get_device_properties(0).total_memory))
print("Loading Kokoro...", flush=True)
PIPELINE = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M", device="cuda")
LOCK = threading.Lock()  # one model instance; keep inference serial
for _ in PIPELINE("Warming up.", voice="af_heart"):  # first call is ~5 s (CUDA init)
    pass
torch.cuda.empty_cache()
print("Kokoro ready.", flush=True)

app = FastAPI()


_MIXES = {}


def _resolve_voice(spec):
    """A plain name or equal-weight "a,b" list goes to Kokoro as is; a
    weighted "name:w,..." list becomes the weighted mean of the voices'
    style tensors. Caller holds LOCK."""
    if ":" not in spec:
        return spec
    if spec not in _MIXES:
        parts = [p.rsplit(":", 1) for p in spec.split(",")]
        weights = torch.tensor([float(w) for _, w in parts])
        packs = torch.stack([PIPELINE.load_single_voice(name.strip()).float().cpu() for name, _ in parts])
        weights = (weights / weights.sum()).view(-1, *([1] * (packs.dim() - 1)))
        _MIXES[spec] = (packs * weights).sum(dim=0)
    return _MIXES[spec]


class TTSRequest(BaseModel):
    text: str
    voice: str = "af_heart"
    speed: float = 1.0


def _pcm_stream(req):
    with LOCK, torch.inference_mode():
        try:
            for result in PIPELINE(req.text, voice=_resolve_voice(req.voice), speed=req.speed):
                audio = result.audio.cpu().numpy() if result.audio is not None else None
                if audio is not None and len(audio):
                    yield (np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes()
        finally:
            torch.cuda.empty_cache()  # give the cache back (see the module docstring)


@app.get("/health")
def health():
    mb = lambda n: round(n / 2**20)
    return {"status": "ok", "voices": VOICES, "gpu_mb": {
        "allocated": mb(torch.cuda.memory_allocated()), "reserved": mb(torch.cuda.memory_reserved()),
        "peak_allocated": mb(torch.cuda.max_memory_allocated()), "cap": mb(MAX_GPU_GB * 2**30)}}


@app.post("/tts/stream")
def tts_stream(req: TTSRequest):
    return StreamingResponse(_pcm_stream(req), media_type="audio/L16;rate=24000;channels=1")


@app.post("/tts")
def tts(req: TTSRequest):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(b"".join(_pcm_stream(req)))
    return Response(content=buf.getvalue(), media_type="audio/wav")
