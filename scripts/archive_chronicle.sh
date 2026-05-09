#!/bin/zsh
set -euo pipefail

ROOT="${CODEX_HOME:-$HOME/.codex}/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough"
SRC="${TMPDIR%/}/chronicle/screen_recording"
FRAMES="$ROOT/frames"
META="$ROOT/metadata"
LOGS="$ROOT/logs"
MANIFEST="$ROOT/manifest.jsonl"
QUALITY="${CHRONICLE_REM_JPEG_QUALITY:-38}"
MAX_WIDTH="${CHRONICLE_REM_MAX_WIDTH:-1440}"

mkdir -p "$FRAMES" "$META" "$LOGS"
touch "$MANIFEST"

if [[ ! -d "$SRC" ]]; then
  echo "$(date -u +%FT%TZ) missing source $SRC" >> "$LOGS/archive.log"
  exit 0
fi

archive_frame() {
  local src="$1"
  local rel="${src#$SRC/}"
  local dest

  if [[ "$rel" == *"-latest.jpg" ]]; then
    local stamp
    stamp="$(date -u -r "$src" +%Y%m%dT%H%M%SZ)"
    dest="$FRAMES/latest_snapshots/${stamp}-${rel:t}"
  else
    dest="$FRAMES/$rel"
  fi

  [[ -f "$dest" ]] && return 0
  mkdir -p "${dest:h}"

  local tmp="${dest}.tmp"
  if /usr/bin/sips -s format jpeg -s formatOptions "$QUALITY" --resampleWidth "$MAX_WIDTH" "$src" --out "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$dest"
  else
    rm -f "$tmp"
    cp -p "$src" "$dest"
  fi

  printf '{"archived_at":"%s","source":"%s","archive":"%s","bytes":%s}\n' \
    "$(date -u +%FT%TZ)" "$src" "$dest" "$(stat -f%z "$dest" 2>/dev/null || echo 0)" >> "$MANIFEST"
}

archive_meta() {
  local src="$1"
  local rel="${src#$SRC/}"
  local dest="$META/$rel.gz"

  mkdir -p "${dest:h}"
  if [[ ! -f "$dest" || "$src" -nt "$dest" ]]; then
    /usr/bin/gzip -c "$src" > "${dest}.tmp"
    mv "${dest}.tmp" "$dest"
  fi
}

find "$SRC" -type f -name '*.jpg' -print0 | while IFS= read -r -d '' f; do
  archive_frame "$f"
done

find "$SRC" -type f \( -name '*.ocr.jsonl' -o -name '*.capture.json' \) -print0 | while IFS= read -r -d '' f; do
  archive_meta "$f"
done

{
  echo "last_run_utc=$(date -u +%FT%TZ)"
  echo "source=$SRC"
  echo "frames=$(find "$FRAMES" -type f -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')"
  echo "metadata=$(find "$META" -type f -name '*.gz' 2>/dev/null | wc -l | tr -d ' ')"
  echo "size=$(du -sh "$ROOT" 2>/dev/null | awk '{print $1}')"
} > "$ROOT/status.txt"

