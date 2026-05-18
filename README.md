# Codex Chronicle REM

Tiny persistent visual memory for Codex Chronicle on macOS.

<img width="1188" height="894" alt="SCR-20260517-ceir" src="https://github.com/user-attachments/assets/684b0e78-c0f8-4e6a-a98e-81d1f4b4c1e2" />


Chronicle already keeps fast summaries for agents and a rolling temp screen buffer. This project adds the missing durable layer:

- archives every Chronicle frame from `$TMPDIR/chronicle/screen_recording`
- recompresses screenshots with built-in `sips`
- keeps OCR/capture sidecars as gzip
- stores detail under `~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough`
- gives humans a native menu-bar viewer with a window, search, slider, and play/pause
- gives Codex a natural path to inspect old detail only when summaries are not enough

The normal Chronicle summaries stay the default. This archive is intentionally named so agents do not load it casually.

## Install

```bash
git clone https://github.com/samihalawa/codex-chronicle-rem.git
cd codex-chronicle-rem
./scripts/install.sh
```

After install:

- app: `~/Applications/Chronicle REM.app`
- archive: `~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough`
- background job: `~/Library/LaunchAgents/com.samihalawa.chronicle-rem-archive.plist`

Open the viewer:

```bash
open "$HOME/Applications/Chronicle REM.app"
```

Run one archive pass manually:

```bash
./scripts/archive_chronicle.sh
```

Make an optional compressed timelapse from recent archived frames:

```bash
./scripts/make_timelapse.sh
```

## Agent Use

Codex should continue using Chronicle summaries first:

```text
~/.codex/memories/extensions/chronicle/resources/
```

Only inspect this heavy detail archive when the summaries are not enough:

```text
~/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough/
```

Useful files:

- `status.txt` quick archive health
- `manifest.jsonl` archived-frame index
- `frames/` compressed persistent screenshots
- `metadata/` compressed OCR/capture sidecars

## Computer Use Proof

When Codex desktop Computer Use looks broken, prove the runtime path before comparing UI plugin cards:

1. Load the Computer Use toolset for the current turn.
2. Run a non-invasive probe: `list_apps`, then `get_app_state` on Finder.
3. Treat a readable Finder state as the success proof, even if plugin settings still look stale.
4. If the probe fails after reinstall, compare the cached Computer Use plugin build with the installed helper build and re-check macOS Accessibility plus Screen Recording for both Codex and Codex Computer Use.

## Build

```bash
make app
make package
make release
```

`make release` builds the signed `Chronicle-REM.app.zip` and `Chronicle-REM.dmg` artifacts in `dist/`.

Requires macOS, Swift, `sips`, and `iconutil`. `ffmpeg` is optional for timelapse export.
