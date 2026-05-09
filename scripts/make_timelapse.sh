#!/bin/zsh
set -euo pipefail

ROOT="${CODEX_HOME:-$HOME/.codex}/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough"
OUT_DIR="$ROOT/videos"
mkdir -p "$OUT_DIR"

command -v ffmpeg >/dev/null || {
  echo "ffmpeg not found"
  exit 1
}

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LIST="$(mktemp)"
find "$ROOT/frames" -type f -name '*.jpg' | sort | tail -1000 | while read -r f; do
  printf "file '%s'\n" "$f" >> "$LIST"
done

OUT="$OUT_DIR/chronicle-rem-${STAMP}.mp4"
ffmpeg -hide_banner -loglevel error -y -r 6 -f concat -safe 0 -i "$LIST" -vf "scale='min(1440,iw)':-2" -c:v libx264 -preset veryfast -crf 32 -pix_fmt yuv420p "$OUT"
rm -f "$LIST"
echo "$OUT"

