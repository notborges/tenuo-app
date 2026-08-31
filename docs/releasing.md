# Releasing Tenuo

The release script packages a Developer ID build as a ZIP or DMG and can submit
it to Apple's notarization service.

## Prerequisites

- Xcode with the macOS SDK used by the project.
- A Developer ID Application certificate.
- An Apple Developer team ID.
- A `notarytool` Keychain profile.
- A Sparkle appcast and EdDSA signing key if updates are enabled.

Keep all certificates, private keys, credentials, and appcast signing keys out
of the repository.

## Configure signing

```sh
cp Local.xcconfig.example Local.xcconfig
```

Set `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` in `Local.xcconfig`.

Create the notarytool profile once:

```sh
xcrun notarytool store-credentials tenuo-notary \
  --apple-id you@example.com \
  --team-id ABCDE12345 \
  --password APP_SPECIFIC_PASSWORD
```

## Package

```sh
TENUO_TEAM_ID=ABCDE12345 ./scripts/release.sh
TENUO_TEAM_ID=ABCDE12345 ./scripts/release.sh --dmg
TENUO_TEAM_ID=ABCDE12345 ./scripts/release.sh --no-notarize
```

`TENUO_SIGN_IDENTITY` selects a specific Developer ID identity and
`TENUO_KEYCHAIN_PROFILE` selects the notarytool profile. The default profile
name is `tenuo-notary`.

The script verifies the signature, Hardened Runtime, notarization ticket,
stapling, and Gatekeeper assessment before it finishes.

## Sparkle

Source builds leave `TENUO_FEED_URL` empty and do not check for updates. A
distributed build needs an appcast URL and `SUPublicEDKey` in its build
configuration before Sparkle can install updates. Generate and protect the
private EdDSA key outside this repository.
