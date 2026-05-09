# Codex Chronicle REM

Tiny persistent visual memory for Codex Chronicle on macOS.

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

## Build

```bash
make app
make package
```

Requires macOS, Swift, and `sips`. `ffmpeg` is optional for timelapse export.

