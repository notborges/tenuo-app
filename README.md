# Tenuo

Tenuo is a macOS menu bar utility for keyboard layers. Hold a trigger key to
turn ordinary keys into navigation, editing, or custom shortcuts, then release
it to return to the normal keyboard.

## Features

- Multiple profiles with up to six triggered layers each.
- Caps Lock, modifier keys, or any catalogued key as a layer trigger.
- Hold, tap, Hyper, blocked, transparent, and modifier-aware mappings.
- A visual editor, layer cheat sheet, profile import, and profile export.
- Optional Sparkle updates for builds configured by a distributor.

## Requirements

- macOS 15 or later.
- Xcode 26 or later to build from source.
- Accessibility permission for the app.

Tenuo uses a system-wide `CGEventTap`, so it is not sandboxed. Caps Lock is
temporarily remapped to F18 with `hidutil` while Tenuo is running. The app does
not read keyboard input outside the event stream needed to implement layers.

## Build

Open `Tenuo.xcodeproj` in Xcode, select the `Tenuo` scheme, and run it. The
command-line equivalents are:

```sh
xcodebuild -project Tenuo.xcodeproj -scheme Tenuo -configuration Debug build
xcodebuild -project Tenuo.xcodeproj -scheme Tenuo -configuration Debug test
```

The default configuration uses ad-hoc signing, which means macOS may ask for
Accessibility permission again after a rebuild. For a stable local identity:

```sh
cp Local.xcconfig.example Local.xcconfig
```

Then set `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` in the ignored file.

## Source layout

```text
Tenuo/
  App/        Application lifecycle and windows
  Core/       Profile models, presets, settings, and the layer engine
  System/     Event tap, Caps Lock remapping, permissions, and updates
  UI/         SwiftUI views and AppKit controllers
TenuoTests/   Core behavior and persistence tests
scripts/      Release tooling
tools/icon/   Icon source and export tooling
```

The test target compiles `Core` directly so running tests never launches the
app, installs an event tap, or changes the keyboard mapping on the test
machine.

## Release builds

`scripts/release.sh` creates a Developer ID archive and can notarize a ZIP or
DMG. It expects a local signing identity, an Apple Developer team ID, and a
`notarytool` Keychain profile. See [docs/releasing.md](docs/releasing.md).

Sparkle is disabled for source builds. A distributor must provide an appcast
URL and update signing key before enabling it; no signing credentials belong in
this repository.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
Bug reports involving keyboard input should include the macOS version, the
trigger and mapping involved, and whether Secure Input was active. Do not
include private keyboard data or signing credentials.

## License

Tenuo is released under the [MIT License](LICENSE).
