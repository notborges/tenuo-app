# Tenuo

Tenuo is a macOS menu bar app for keyboard layers. Hold a layer key, use the
keys assigned to that layer, and release it to return to normal typing. Caps
Lock is the default layer key, but you can choose another supported key.

## Download

Download the official app from [tenuo.app](https://tenuo.app) or
[GitHub Releases](https://github.com/notborges/tenuo-app/releases/latest).
Both provide the same signed and notarized DMG, with automatic update support.
You can also build Tenuo from source; source builds do not use the official
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
- Hold, toggle, and one-shot layers are free.
- Pro adds Mac actions, app-specific mapping overrides, profile history, and
  optional iCloud profile sync between Macs.
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

## Editing several mappings

Command-click keys on the keyboard or in the mapping list to select more than
one. Click empty space or press Escape to deselect.

Use Copy and Paste in the Edit menu, or right-click a key. A single copied
mapping can be pasted onto one or several selected keys. To copy a group to
another layer, switch layers and choose **Paste to original keys**. Copy only
includes assignments in the current layer and application context; inherited
mappings and unassigned keys are skipped. The mapping clipboard lasts until
another copy operation or until Tenuo quits.

**Clear mappings** removes the selected assignments. In an application override,
**Use Default** removes those overrides instead. Each paste or clear operation
can be undone in one step with Command-Z.

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

Debug builds enable Pro features for local development. iCloud sync also needs
CloudKit provisioning; the default source build leaves it unavailable.
To develop sync, register app IDs and an iCloud container under your Apple
Developer team, enable CloudKit and Push Notifications, and set your container
identifier in `Tenuo/Resources/TenuoCloud.entitlements`. Enable the CloudKit
signing options shown in `Local.xcconfig.example`, then let Xcode manage the
matching provisioning profiles.

Debug uses CloudKit's Development environment; Release uses Production. A
Developer ID release must include its CloudKit provisioning profile, preserve
the Production entitlements through Xcode export, and have its container's
schema deployed to Production.

## Preview the Free interface

Debug builds normally enable Pro. To inspect the Free editor and its upgrade
prompts without changing your regular profiles or license, launch:

```sh
"/path/to/Tenuo Dev.app/Contents/MacOS/Tenuo Dev" --ui-preview --free-preview
```

The UI preview uses separate sample profiles and does not start keyboard
remapping or sync. Settings can be opened from the editor. Free preview does
not read or write a saved license or contact Polar; its license form is for
visual review only. Quit and omit `--free-preview` to return to the Pro preview.
The flag has no effect in Release builds.

## Permissions and privacy

Tenuo installs a system-wide `CGEventTap` so it can pass, suppress, or rewrite
keyboard events. It is intentionally not sandboxed and needs Accessibility
access; it does not need Input Monitoring.

Keyboard events are processed locally. Tenuo does not record or transmit
keystrokes. Profiles stay local unless you export them or enable Pro's iCloud
sync. Sync stores profile definitions in your private iCloud database. Active
profile selection, app preferences, profile history, file-access bookmarks,
and local target replacements stay on each Mac.

Official builds can contact Polar when a Pro license is activated or checked.
The license record stays in the macOS Keychain; keyboard events and profiles
are not sent.

When Caps Lock is used as a layer trigger, Tenuo temporarily maps it to F18
with `hidutil` while it is running, then restores the previous mapping when it
shuts down. Other trigger keys do not use this remapping.

Official builds use Sparkle for updates, whether downloaded from tenuo.app or
GitHub Releases. Source builds have no update feed configured and do not check
for updates by default.

Source builds leave official Polar licensing unconfigured. Debug builds enable
a local Pro preview; Release builds require configured Polar licensing and an
active entitlement. All Pro code is included in this repository. Apple's
authorization to use a CloudKit container comes from signing and provisioning,
not from enabling the Pro preview.

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

## Check sync on one Mac

Build a signed Debug app with Development CloudKit provisioning, sign into
an Apple Account in macOS, then run:

```sh
python3 scripts/check-sync.py --app "/path/to/Tenuo Dev.app"
```

The runner compiles the production storage, sync controller, and CloudKit
transport into a temporary diagnostic app using the supplied build's signing
identity and provisioning profile. It requires the matching private signing
key in your Keychain. It creates two isolated SQLite clients and a unique zone
in the private **Development** database. Your normal profiles are untouched.
Production-provisioned apps are rejected.

Checks cover the Free access gate, connection review before upload, edits,
paused edits, conflicts and resolution, deletion, Pro loss, and pending edits
surviving a database reopen. The test controls each CloudKit engine's scheduling
to simulate two devices deterministically; the shipping app retains automatic
sync. This follows [Apple's CKSyncEngine testing approach](https://github.com/apple/sample-cloudkit-sync-engine).
The runner removes its cloud zone and temporary files afterward. If cloud
cleanup fails, it reports the exact Development zone to remove.

This verifies real CloudKit round trips on one Mac. Background push delivery
between physical Macs, Production schema configuration, and Release license
activation still require separate release checks.
