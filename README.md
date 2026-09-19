# Tenuo

Tenuo is a macOS app for setting up keyboard layers in a visual editor. Pick a
key to hold, assign shortcuts to the keys around it, and release it to return
to typing.

[Download](https://tenuo.app) · [Documentation](https://tenuo.app/docs) ·
[Releases](https://github.com/notborges/tenuo-app/releases)

## Features

- **Visual mapping editor.** Assign keys and shortcuts without writing config
  files. Select several keys to edit together, copy mappings between layers,
  and undo changes.
- **Keyboard layers.** Choose a trigger, hold it to use a layer, or set up
  toggle and one-shot layers. Give the trigger a separate action when tapped.
- **Hyper key.** Send Control, Option, Command, and Shift together from one
  held key, with custom mappings in the same layer.
- **Profiles.** Keep different keyboard setups, switch from the menu bar,
  and import or export them to share with others.
- **On-screen cheat sheet.** Hold a layer key to see its mappings while you
  learn them.

These features are free. **Tenuo Pro** adds:

- Open apps, files, folders, and websites, or run Apple Shortcuts from a key.
- Assign different mappings for each app.
- Compare and restore earlier versions of your profiles.
- Sync profiles between Macs through iCloud.

All source code, including Pro, is available under the [MIT License](LICENSE).

## Install

Download the signed and notarized app from [tenuo.app](https://tenuo.app) or
[GitHub Releases](https://github.com/notborges/tenuo-app/releases/latest).
Both downloads contain the same DMG and support automatic updates.
Requires macOS 15 or later.

Open Tenuo, grant Accessibility access when prompted, then open the editor
from the menu bar. The default profile uses Caps Lock to activate a layer
and sends Escape when you tap it.

## Privacy

Tenuo needs Accessibility access to remap keys. It processes keyboard events
on your Mac without recording or transmitting keystrokes. The app has no
analytics or telemetry.

Profiles stay on your Mac unless you export them or enable iCloud sync.
Official builds contact Polar for Pro license activation and validation,
and use Sparkle to check for app updates.

## Build from source

With Xcode 26 or later, open `Tenuo.xcodeproj`, select the `Tenuo` scheme,
and run. You can also build from the terminal:

```sh
xcodebuild -project Tenuo.xcodeproj -scheme Tenuo -configuration Debug build
```

Debug builds run as **Tenuo Dev**, with separate preferences and Accessibility
permission. Quit the official app before running Tenuo Dev so both apps don't
handle the same keyboard events.

Debug builds enable Pro features for development. iCloud sync requires your
own CloudKit provisioning. Source builds don't use the official update feed.
See [CONTRIBUTING.md](CONTRIBUTING.md) for signing, tests, and development setup.

## Contributing

Bug reports and pull requests are welcome. Include your macOS version and
steps to reproduce the issue. For keyboard issues, include the keyboard type
and macOS input source.

Read the [contribution guidelines](CONTRIBUTING.md) and
[Code of Conduct](CODE_OF_CONDUCT.md). Report security issues through the
[security policy](SECURITY.md).

## License

The code is [MIT licensed](LICENSE). The Tenuo name and logos have a separate
[trademark policy](TRADEMARKS.md). See [third-party notices](THIRD-PARTY-NOTICES.md)
for dependencies and assets.
