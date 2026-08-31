#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"

ACTOOL="$(xcrun --find actool 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer/usr/bin/actool)"
[[ -x "$ACTOOL" ]] || { echo "actool not found: install Xcode 26 or later." >&2; exit 1; }

CONCEPT=sa-stack                       # the chosen mark
FILL="srgb:0.055,0.055,0.063,1.000"    # near-black, as the category uses
PREVIEW_DIR="$ROOT/tools/icon/preview"

echo "==> App icon"
rm -rf Tenuo.icon && mkdir -p Tenuo.icon/Assets
xcrun swift render-html.swift concepts.html Tenuo.icon/Assets/glyph.png 1024 "$CONCEPT"

cat > Tenuo.icon/icon.json <<JSON
{
  "fill" : { "automatic-gradient" : "$FILL" },
  "groups" : [
    {
      "layers" : [ { "image-name" : "glyph.png", "name" : "Keycaps" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "circles" : [ "watchOS" ], "squares" : [ "iOS", "macOS" ] }
}
JSON

BUILD=$(mktemp -d)
"$ACTOOL" Tenuo.icon Assets.xcassets --compile "$BUILD" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$BUILD/partial.plist" \
    --app-icon Tenuo --include-all-app-icons --enable-on-demand-resources NO \
    --development-region en --target-device mac \
    --minimum-deployment-target 15.0 --platform macosx > /dev/null

mkdir -p "$ROOT/Tenuo/Resources"
cp "$BUILD/Assets.car" "$ROOT/Tenuo/Resources/Assets.car"
cp "$BUILD/Tenuo.icns" "$ROOT/Tenuo/Resources/Tenuo.icns"
echo "    Assets.car, Tenuo.icns -> Tenuo/Resources"

echo "==> Preview artwork"
mkdir -p "$PREVIEW_DIR"
for size in 1024 512 256 128 64; do
    xcrun swift render-html.swift concepts.html "$PREVIEW_DIR/caps-$size.png" "$size" caps 1024
done
echo "    tools/icon/preview/caps-{1024,512,256,128,64}.png"

xcrun swift render-html.swift concepts.html "$PREVIEW_DIR/TenuoTemplate.png" 18 menubar 1024
xcrun swift render-html.swift concepts.html "$PREVIEW_DIR/TenuoTemplate@2x.png" 36 menubar 1024
xcrun swift render-html.swift concepts.html "$PREVIEW_DIR/TenuoTemplate@3x.png" 54 menubar 1024
echo "    tools/icon/preview/TenuoTemplate{,@2x,@3x}.png"

cp "$PREVIEW_DIR/TenuoTemplate.png"    "$ROOT/Tenuo/Resources/"
cp "$PREVIEW_DIR/TenuoTemplate@2x.png" "$ROOT/Tenuo/Resources/"
echo "    TenuoTemplate{,@2x}.png -> Tenuo/Resources"

xcrun swift render-html.swift concepts.html "$ROOT/Tenuo/Resources/TenuoMark.png" 26 caps 1024
xcrun swift render-html.swift concepts.html "$ROOT/Tenuo/Resources/TenuoMark@2x.png" 52 caps 1024
echo "    TenuoMark{,@2x}.png -> Tenuo/Resources"

rm -rf "$BUILD"
echo
echo "Done."
