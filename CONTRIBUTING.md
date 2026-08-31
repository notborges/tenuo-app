# Contributing

Thanks for helping improve Tenuo. Keep changes focused and explain user-visible
behavior in the pull request description.

Before opening a pull request:

1. Run the unit tests.
2. Run `xcrun swift-format lint --configuration .swift-format --recursive Tenuo TenuoTests`.
3. Run `git diff --check`.
4. Manually test changes that affect keyboard events, permissions, windows, or
   persistence. The relevant cases are listed in `MANUAL-TESTS.md`.

Core behavior belongs in `Tenuo/Core`. Add tests for important behavior and
regressions; UI layout and trivial accessors do not need tests. Keep Core
independent from AppKit and SwiftUI. Changes to the event tap or `hidutil`
integration should document failure and recovery behavior.

Do not commit signing identities, provisioning files, notarization credentials,
personal profiles, or local configuration.
