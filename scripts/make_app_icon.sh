#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output.icns>" >&2
  exit 1
fi

OUT="$1"
OUT_DIR="${OUT:h}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-icon.XXXXXX")"
SWIFT_FILE="$STAGE/make_app_icon.swift"
BASE_PNG="$STAGE/AppIcon-1024.png"
ICONSET="$STAGE/AppIcon.iconset"

trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT_DIR" "$ICONSET"

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fatalError("missing output path")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 40, dy: 40), xRadius: 230, yRadius: 230)
NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.11, alpha: 1).setFill()
rounded.fill()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.68, alpha: 1),
    NSColor(calibratedRed: 0.70, green: 0.24, blue: 0.60, alpha: 1)
])!
gradient.draw(in: rounded, angle: 35)

let innerGlow = NSBezierPath(roundedRect: bounds.insetBy(dx: 112, dy: 112), xRadius: 180, yRadius: 180)
NSColor.white.withAlphaComponent(0.10).setFill()
innerGlow.fill()

let ring = NSBezierPath(ovalIn: NSRect(x: 228, y: 228, width: 568, height: 568))
NSColor.white.withAlphaComponent(0.18).setStroke()
ring.lineWidth = 24
ring.stroke()

if let symbol = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Chronicle REM") {
    let configured = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold, scale: .large)
    ) ?? symbol
    NSColor.white.set()
    configured.draw(in: NSRect(x: 282, y: 282, width: 460, height: 460))
}

let spark = NSBezierPath()
spark.move(to: NSPoint(x: 360, y: 308))
spark.curve(
    to: NSPoint(x: 650, y: 690),
    controlPoint1: NSPoint(x: 390, y: 520),
    controlPoint2: NSPoint(x: 560, y: 650)
)
NSColor.white.withAlphaComponent(0.16).setStroke()
spark.lineWidth = 20
spark.lineCapStyle = .round
spark.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}

try png.write(to: output)
SWIFT

swift "$SWIFT_FILE" "$BASE_PNG"

resize() {
  local size="$1"
  local out_name="$2"
  /usr/bin/sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET/$out_name" >/dev/null
}

resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
resize 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUT"
