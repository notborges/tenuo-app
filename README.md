# Tenuo

Tenuo is a macOS menu bar app for keyboard layers. Hold a layer key, use the
keys assigned to that layer, and release it to return to normal typing. Caps
Lock is the default layer key, but you can choose another supported key.

## Download

Official signed builds and product information are distributed separately at
[tenuo.app](https://tenuo.app). This repository contains the source code;
source builds are not the official signed distribution and do not use its
update feed by default.

## Features

- One base layer and up to six triggered layers per profile.
- Multiple profiles that can be switched from the menu bar.
- Caps Lock, a modifier, or another key as a layer trigger, with optional
  modifier requirements such as Shift + Caps Lock.
- Key mappings that send another key or shortcut, pass through, block the key,
  or send Hyper (Control + Option + Command + Shift).
- An optional tap action for a layer key, such as sending Escape when Caps Lock
  is tapped.
- A visual editor, an optional active-layer view while holding a trigger, and
  JSON profile import and export.
- Launch at login.

## Getting started

1. Launch Tenuo. It stays in the menu bar.
2. Open System Settings when Tenuo asks for Accessibility access, then enable
   Tenuo under Privacy & Security → Accessibility.
3. Open the editor from the menu bar and choose a profile and layer.
4. Hold the layer's trigger and press a mapped key. Release the trigger to
   return to normal typing.

The default profile uses Caps Lock as its layer key and sends Escape when Caps
Lock is tapped. To change this, select a layer and edit its Trigger settings.
Modifier triggers continue to work as modifiers. A non-modifier trigger is
consumed while held, so give it a tap action if it should do something when
tapped.

## Requirements

- macOS 15 or later.
- Xcode 26 or later to build from source.
- Accessibility access to remap keys.

## Build from source

Open `Tenuo.xcodeproj` in Xcode, select the `Tenuo` scheme, and run it. The
command-line equivalents are:

```sh
xcodebuild -project Tenuo.xcodeproj -scheme Tenuo -configuration Debug build
xcodebuild \
  -project Tenuo.xcodeproj \
  -scheme Tenuo \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

The Debug build uses the separate `app.tenuo.dev` bundle identifier and is
shown as Tenuo Dev. Its Accessibility permission and local preferences are
separate from the official Release build, which uses `app.tenuo`. Both apps
can be installed on the Mac at the same time, but only one should be running
at a time because keyboard event handling and the Caps Lock remap are
system-wide.

The default source configuration uses ad-hoc signing. macOS may ask for
Accessibility access again after an ad-hoc rebuild because the app's code
signature changes. For a stable local identity:

```sh
cp Local.xcconfig.example Local.xcconfig
```

Then set `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` in the ignored file.

## Permissions and privacy

Tenuo installs a system-wide `CGEventTap` so it can pass, suppress, or rewrite
keyboard events. It is intentionally not sandboxed and needs Accessibility
access; it does not need Input Monitoring.

Keyboard events are processed locally. Tenuo does not record or transmit
keystrokes, and profiles and settings stay on the Mac unless you export a
profile yourself.

When Caps Lock is used as a layer trigger, Tenuo temporarily maps it to F18
with `hidutil` while it is running, then restores the previous mapping when it
shuts down. Other trigger keys do not use this remapping.

Source builds have no update feed configured and do not check for updates. An
official build can be configured to use Sparkle for updates; update checks are
off until a feed is provided.

## Development

The source is organized by responsibility:

```text
Tenuo/
  App/        Application lifecycle and windows
  Core/       Profile models, presets, settings, and the layer engine
  System/     Event tap, key remapping, permissions, and updates
  UI/         SwiftUI views and AppKit controllers
TenuoTests/   Core behavior and persistence tests
scripts/      Development helpers
tools/icon/   Icon source and export tooling
```

The test target compiles `Core` directly. Running the tests does not launch the
app, install an event tap, or change the keyboard mapping on the test machine.

Run the formatter check before opening a pull request:

```sh
xcrun swift-format lint \
  --configuration .swift-format \
  --recursive Tenuo TenuoTests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution guidelines.

## Project policies

- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Third-party notices](THIRD-PARTY-NOTICES.md)
- [Trademark policy](TRADEMARKS.md)

## License

Tenuo's source code is released under the [MIT License](LICENSE).

The Tenuo name and logos are covered separately by the
[trademark policy](TRADEMARKS.md).
