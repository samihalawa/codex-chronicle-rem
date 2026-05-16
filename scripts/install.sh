#!/bin/zsh
set -euo pipefail

REPO_DIR="${0:A:h:h}"
ROOT="${CODEX_HOME:-$HOME/.codex}/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough"
APP="$HOME/Applications/Chronicle REM.app"
PLIST="$HOME/Library/LaunchAgents/com.samihalawa.chronicle-rem-archive.plist"

mkdir -p "$ROOT/scripts" "$ROOT/viewer" "$ROOT/logs" "$HOME/Applications" "$HOME/Library/LaunchAgents"

cp "$REPO_DIR/scripts/archive_chronicle.sh" "$ROOT/scripts/archive_chronicle.sh"
cp "$REPO_DIR/scripts/make_timelapse.sh" "$ROOT/scripts/make_timelapse.sh"
cp "$REPO_DIR/src/ChronicleREM.swift" "$ROOT/viewer/ChronicleREM.swift"
cp "$REPO_DIR/README.md" "$ROOT/README.md"
chmod +x "$ROOT/scripts/"*.sh

(cd "$REPO_DIR" && make app)

sed "s#__HOME__#$HOME#g" "$REPO_DIR/launchagents/com.samihalawa.chronicle-rem-archive.plist.template" > "$PLIST"

/bin/launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST"
/bin/launchctl kickstart -k "gui/$(id -u)/com.samihalawa.chronicle-rem-archive"

"$ROOT/scripts/archive_chronicle.sh"

echo "Installed Chronicle REM"
echo "App: $APP"
echo "Archive: $ROOT"
echo "LaunchAgent: $PLIST"
