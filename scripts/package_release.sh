#!/bin/zsh
set -euo pipefail

REPO_DIR="${0:A:h:h}"
APP_NAME="Chronicle REM"
APP_DIR="$HOME/Applications/$APP_NAME.app"
DIST_DIR="$REPO_DIR/dist"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-release.XXXXXX")"
APP_STAGE="$STAGE_ROOT/$APP_NAME.app"
DMG_STAGE="$STAGE_ROOT/dmg"
ZIP_OUT="$DIST_DIR/Chronicle-REM.app.zip"
DMG_OUT="$DIST_DIR/Chronicle-REM.dmg"
SIGN_IDENTITY="${CHRONICLE_REM_SIGN_IDENTITY:-39CAA87C5412450DA8B2A01652A3BC3A42C232BC}"

trap 'rm -rf "$STAGE_ROOT"' EXIT

pkill -f "$APP_DIR/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true

cd "$REPO_DIR"
make app

codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"

mkdir -p "$DIST_DIR" "$DMG_STAGE"
rm -f "$ZIP_OUT" "$DMG_OUT"

/usr/bin/ditto "$APP_DIR" "$APP_STAGE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_STAGE" "$ZIP_OUT"

ln -s /Applications "$DMG_STAGE/Applications"
/usr/bin/ditto "$APP_STAGE" "$DMG_STAGE/$APP_NAME.app"
/usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUT" >/dev/null

codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_OUT"

echo "$ZIP_OUT"
echo "$DMG_OUT"
