# Contributing

Thanks for helping improve Tenuo. Keep changes focused and explain user-visible
behavior in the pull request description.

Before opening a pull request:

1. Run the unit tests.
2. Run `xcrun swift-format lint --configuration .swift-format --recursive Tenuo TenuoTests`.
3. Run `git diff --check`.

Core behavior belongs in `Tenuo/Core`. Add tests for important behavior and
regressions; UI layout and trivial accessors do not need tests. Keep Core
independent from AppKit and SwiftUI. Changes to the event tap or `hidutil`
integration should document failure and recovery behavior and explain how the
change was verified.

Do not commit signing identities, provisioning files, notarization credentials,
personal profiles, or local configuration.

## Build and test

Use Xcode 26 or later. Run the tests without signing:

```sh
xcodebuild \
  -project Tenuo.xcodeproj \
  -scheme Tenuo \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

The tests run without launching the app or changing your keyboard mappings.

Caps Lock source mappings use the same verified `hidutil` Caps Lock → F18
bridge as Caps Lock triggers. The bridge is needed for any nontransparent
Caps Lock mapping, including app overrides. With no mapping in the active
layers, the event tap toggles the native lock state through IOKit; it never
forwards the bridge's F18 event. A failed native toggle is logged; disabling
Tenuo restores the original HID mapping and native Caps Lock behavior.
Bridge installation and restoration failures use the one-second retry. Removing
the bridge waits for a held Caps Lock to be released. Disable releases held
outputs immediately and keeps the event tap until the bridge is restored and consumed sources release;
sleep, wake, and keyboard changes reconcile missing releases with HID state.
Quit or lost Accessibility permission removes the tap immediately.

Output modifiers are posted as real modifier presses around the output key,
because hold shortcuts watch modifier presses rather than event flags alone.

For event changes, verify key-down/key-up output, both modifier sides held
together, layer/profile changes during a press, and disable during a press.
Use a dictation app to check its hold and double-tap shortcuts manually; the
unit tests exercise event lifecycles without starting a remapper.

The source configuration uses ad-hoc signing. Rebuilding can require granting
Accessibility access again. To use your Apple Development identity, copy
`Local.xcconfig.example` to `Local.xcconfig` and set `CODE_SIGN_IDENTITY` and
`DEVELOPMENT_TEAM`. Git ignores this file.

## Source layout

- `Tenuo/App`: application lifecycle and windows.
- `Tenuo/Core`: profiles, persistence, and the layer engine.
- `Tenuo/System`: keyboard events, permissions, licensing, sync, and updates.
- `Tenuo/UI`: SwiftUI views and AppKit controllers.
- `TenuoTests`: behavior and regression tests.
- `scripts`: development helpers.
- `tools/icon`: icon source and export tooling.

## UI previews

Launch a Debug build with sample profiles and keyboard remapping disabled:

```sh
"/path/to/Tenuo Dev.app/Contents/MacOS/Tenuo Dev" --ui-preview
```

Add `--free-preview` to inspect the Free interface and upgrade prompts.
This preview does not access your saved license or contact Polar. Its license
form is for visual review. Preview mode does not start sync; these flags have
no effect in Release builds.

## CloudKit development

Debug builds enable Pro, but sync requires CloudKit signing and provisioning.
Register app IDs and an iCloud container under your Apple Developer team,
enable CloudKit and Push Notifications, and put your container identifier in
`Tenuo/Resources/TenuoCloud.entitlements`. In your local configuration, set
`TENUO_CODE_SIGN_ENTITLEMENTS` to that file and configure signing for your team.

Debug uses the Development CloudKit environment; Release uses Production.
A Developer ID release needs a CloudKit provisioning profile, Production
entitlements, and a schema deployed to Production. Source Release builds also
need Polar configuration and an active license to enable Pro.

To check sync on one Mac, sign into an Apple Account in macOS and supply a
signed Debug build with Development CloudKit provisioning:

```sh
python3 scripts/check-sync.py --app "/path/to/Tenuo Dev.app"
```

The script requires the build's private signing key in your Keychain. It runs
two isolated clients against a temporary zone in your private Development
database and rejects Production builds. It checks connection review, edits,
conflicts, deletion, and Pro access changes without touching your profiles.

The script removes the temporary zone afterward. If cleanup fails, it reports
the zone to remove. This checks CloudKit round trips; it does not verify push
delivery between physical Macs or the Production schema.
