#!/bin/bash
set -euo pipefail

OUT="${1:-/tmp/tenuo-window.png}"
MIN_WIDTH="${2:-800}"
MIN_HEIGHT="${3:-300}"

PID="$(pgrep -f 'Tenuo( Dev)?\.app/Contents/MacOS/Tenuo( Dev)? --ui-preview' | head -1 || true)"
if [[ -z "$PID" ]]; then
    echo "No Tenuo preview is running. Start one with:" >&2
    echo '  "<build-dir>/Tenuo Dev.app/Contents/MacOS/Tenuo Dev" --ui-preview' >&2
    exit 1
fi

WINDOW="$(cat <<SWIFT | xcrun swift - "$PID" "$MIN_WIDTH" "$MIN_HEIGHT"
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let minWidth = Double(CommandLine.arguments[2])!
let minHeight = Double(CommandLine.arguments[3])!

// .optionAll rather than .optionOnScreenOnly: a window on another Space, or
// behind everything else, is still worth capturing.
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner == pid,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, width >= minWidth,
          let height = bounds["Height"] as? Double, height >= minHeight
    else { continue }
    print(number)
    exit(0)
}
exit(1)
SWIFT
)"

if [[ -z "$WINDOW" ]]; then
    echo "No window at least ${MIN_WIDTH}x${MIN_HEIGHT} for pid $PID." >&2
    exit 1
fi

screencapture -x -o -l "$WINDOW" "$OUT"
echo "$OUT"
