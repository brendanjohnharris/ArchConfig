# Fathom desktop --- design & theming spec

A single colour palette ("Fathom") drives every app on this Arch + X11 + XMonad
machine. One generator renders that palette into each app's native config format,
so the terminal, bar, window manager, launchers, file managers, PDF reader, and
even wrapped web apps all share one coherent look. This document is the spec for
how that works and how to extend it.

Stack: XMonad / xmobar / alacritty / dunst / rofi / picom on X11. Dotfiles live in
the bare **ArchConfig** repo (`config` = `git --git-dir=$HOME/ArchConfig --work-tree=$HOME`).

---

## 1. The palette

Colours come from the author's `Fathom.jl` palette (`test/colors.yaml`), cached at
`~/.xmonad/cache/fathom.yaml`. Each base colour has `_light`, `_lighter`, `_dark`,
`_darker` variants (e.g. `baikal_light`). Core tokens and their roles:

| Token | Hex | Role |
|---|---|---|
| `chernoe` | `#282C34` | background (dark base) |
| `chernoe_light` | `#42464D` | raised surfaces, subtle boxes, selected-line bg |
| `abyad_light` | `#D4D4D4` | primary foreground / text |
| `abyad` / `abyad_dark` | `#B4B4B4` / `#959595` | dim text, separators, inactive borders |
| `baikal` | `#6EA0F9` | **blue accent** --- info, links, active borders, titles |
| `bermejo` | `#F93D53` | red --- error, urgent, unstaged/cut |
| `qinghai` | `#88BD69` | green --- success, exec, copied |
| `seohae` | `#FFA829` | orange --- warning, search highlight |
| `ianthina` | `#B97AD7` | purple --- special, descriptions, magenta |
| `mesopelagic` | `#007878` | teal --- cyan slot, battery |
| `playa` | `#F5F1E8` | **the unifying white accent** --- selections, focus, borders |
| `epipelagic` | `#FA9F42` | secondary orange |

**`playa` is the signature.** It is the semantic accent for selection, focus, and
borders across the WM and every launcher/menu (`Colors/Fathom.hs` exports
`colorBorder = playa`, consumed by `xmonad.hs` for focus/active/tab colours). When in
doubt, an accent or selection should be `playa`; an "active/primary" highlight is `baikal`.

---

## 2. The generator

`~/.xmonad/bin/gen-fathom-colors.sh` is the single source of truth. It:

1. Loads the palette (downloads `colors.yaml`, falls back to the cache offline).
2. Writes the Haskell module `~/.xmonad/lib/Colors/FathomColors.hs` (every token as a `String`).
3. Expands `{{token}}` placeholders in each `*.template` into the app's real config.
4. Live-reloads when run inside X: `xrdb -merge ~/.Xresources` + `dunstctl reload`.

### Placeholder syntax

- `{{token}}` --- the hex string, e.g. `{{baikal}}` -> `#6EA0F9`.
- `{{token:fmt}}` --- a numeric conversion, for apps that don't accept hex:

  | Suffix | Output for `baikal` (`#6EA0F9`) | Used by |
  |---|---|---|
  | `:r` `:g` `:b` | `110` / `160` / `249` (0--255 int) | tealdeer |
  | `:rgb` | `110 160 249` (int triple) | *(available)* |
  | `:rgbf` | `0.4314 0.6275 0.9765` (0--1 float triple) | sioyek |

  The conversion is done in `render_template`'s awk via `strtonum`. Add new formats there.

### Rules

- **Never edit a generated file.** Edit its `*.template` and re-render. Generated files
  carry a "Do not edit ... edit this template" header.
- Both the `*.template` **and** the generated output are tracked in ArchConfig (so a fresh
  checkout is themed before the generator ever runs).
- `fish` is special-cased: it wants hex **without** the leading `#`, so the fish output is
  post-processed to strip it.

---

## 3. Themed applications

Every entry below is `template -> generated output`, rendered by the generator:

| App | Template -> output | Colour format |
|---|---|---|
| xmonad | `lib/Colors/FathomColors.hs` (direct write) | hex strings |
| xmobar | `xmobar/{xmobarrc,dual_xmobarrc}.template` | hex |
| alacritty | `alacritty/alacritty.toml.template` | hex |
| X resources | `~/.Xresources.template` | hex |
| dunst | `dunst/dunstrc.template` | hex |
| rofi | `rofi/themes/fathom.rasi.template` | hex |
| GTK 3 / 4 | `gtk-3.0/gtk.css.template`, `gtk-4.0/gtk.css.template` | hex |
| fish | `fish/conf.d/fathom_colors.fish.template` | hex, `#` stripped |
| atuin | `atuin/themes/fathom.toml.template` | hex |
| yazi | `yazi/theme.toml.template` | hex |
| zellij | `zellij/config.kdl.template` | hex |
| lazygit | `lazygit/config.yml.template` | hex |
| tealdeer | `tealdeer/config.toml.template` | RGB ints (`:r/:g/:b`) |
| sioyek | `sioyek/prefs_user.config.template` | RGB floats (`:rgbf`) |
| pake web apps | `webapps/fathom-webapp.css.template` | hex (injected CSS) |

---

## 4. Build & reload flow

The generator runs automatically on an XMonad recompile:

```
M-C-r  ->  xmonad --recompile  ->  ~/.xmonad/build
                                     |- runs gen-fathom-colors.sh   (re-render everything)
                                     '- ghc --make xmonad.hs        (rebuild the WM)
```

`gen-fathom-colors.sh` also live-reloads X resources and dunst, so most changes apply
without a full restart. Apps that only read their config at launch (alacritty, rofi,
yazi, ...) pick up the new colours on their next start.

To re-render without recompiling the WM: just run `~/.xmonad/bin/gen-fathom-colors.sh`.

---

## 5. Adding a new themed app

1. Write `path/to/config.template` using `{{token}}` (or `{{token:fmt}}` if the app needs
   integer/float channels).
2. Add a `render_template ".../config.template" ".../config"` line to
   `gen-fathom-colors.sh` (with a `mkdir -p` if the dir may not exist on a fresh machine).
3. Run the generator; confirm no stray `{{...}}` remain (`grep -l '{{' <output>`).
4. `config add` both the template and the generated output.

---

## 6. Design principles

- **One palette, many formats.** The palette is authored once; every app gets it in the
  syntax it actually wants. No per-app colour drift.
- **`playa` for accents/selection, `baikal` for active/primary, role-coloured status**
  (green=ok, red=error, orange=warn, purple=special).
- **Templates are source; generated files are build artifacts that happen to be tracked.**
- **Don't shadow coreutils.** `ls`, `cat`, `cd` stay as the real binaries; modern tools are
  exposed under distinct names (see below).

---

## 7. CLI tooling

Modern CLI tools, installed via `~/ArchConfig/setup.sh` and `~/install-newtools.sh`,
with shell integration in `~/.bashrc` and `~/.config/fish/config.fish` (all guarded on
`command -v` / `type -q`):

| Tool | Exposed as | Notes |
|---|---|---|
| zoxide | `cd` (fish, via `--cmd cd`), `z`/`zi` | smart dir jumping |
| eza | `ll`/`la`/`lt`/`l` | `ls` untouched |
| bat | `batp` | `cat` untouched |
| fd, ripgrep | `fd`, `rg` | also yazi's search backends |
| atuin | Ctrl-R / Up | local-only history, fathom theme |
| yazi | `y` | file manager; `y` cd's to where you quit |
| zellij | `zj` | multiplexer |
| lazygit | `lg` | git UI |
| tealdeer | `tldr` | fast tldr |
| dua-cli | `dui` | interactive disk usage |

Reader scratchpad (`M-s r`) and the `C-g g` app grid both point at **sioyek**; PDFs default
to sioyek (`$READER`, `xdg-mime`), with okular kept installed as an annotation fallback.

---

## 8. sioyek (important gotcha)

The AUR `sioyek` package is compiled with Arch's `-D_GLIBCXX_ASSERTIONS`, which turns an
upstream latent empty-vector read (ahrm/sioyek#1401) into a **hard abort the moment you
search**. The fix: `~/.local/bin/sioyek-official-update` installs the official prebuilt
binary to `~/.local/opt/sioyek-official/` and drops a `~/.local/bin/sioyek` wrapper that
shadows the AUR binary on PATH (search works; same config + highlight DB). The AUR package
is kept only for its `.desktop`/icon/`/usr/share/sioyek` assets.

Two sioyek config quirks, both handled in the template:
- A `new_command` external-command value **must be wrapped in one pair of double quotes**,
  or sioyek aborts at startup.
- Highlights live in sioyek's SQLite DB, not the PDF; `_embed_annotations` (needs the AUR
  `python-sioyek`) burns them in on demand.

---

## 9. pake web apps

Standalone web apps replace the old `chromium --app` launchers, wrapped with **pake**
(Tauri / WebKitGTK) and themed by the injected `webapps/fathom-webapp.css`.

- **Manifest:** `~/.config/webapps/apps.tsv` --- whitespace-separated
  `name  url  wm_class  flags` (spaces or tabs both parse; `flags` = extra pake flags or
  `TEST` for apps that may not render under WebKitGTK).
- **Builder:** `~/.local/bin/build-webapps.sh [name...]` --- builds each app, extracts the
  binary from pake's `.deb` (no fuse2 needed), installs `~/.local/bin/webapps/<name>` +
  a `.desktop` with a deterministic `StartupWMClass`, and **moves the old chromium
  `.desktop` to `~/.config/webapps/chromium-backup/`** (reusing basenames so
  `gtk-launch <name>` keeps working). `--restore` undoes it.
- **Excluded:** spotify (Widevine DRM) and claude.ai (profile-scoped scratchpad). Video
  calls (Teams/Zoom/Meet) are unreliable under WebKitGTK WebRTC --- flag those `TEST`.
- **pake install:** use a user-owned npm prefix (`npm config set prefix ~/.local`); a `sudo`
  global install into `/usr` breaks because pake writes build deps into its own dir at runtime.

---

## 10. Reproducibility

Everything above is tracked in ArchConfig: templates, generated outputs, the generator,
shell configs, the installer scripts (`install-newtools.sh`, `sioyek-official-update`,
`build-webapps.sh`), and `setup.sh`. Large regenerable artifacts are **not** tracked ---
the pake binaries, the sioyek AppDir, the `~/.local/bin/sioyek` wrapper, and generated
web-app `.desktop`/icons --- because their source-of-truth scripts are.
