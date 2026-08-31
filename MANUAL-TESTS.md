# Manual test checklist

The unit tests cover persistence and the layer engine. These
checks require a real macOS session because they exercise Accessibility,
CoreGraphics, `hidutil`, and application focus.

## First launch

- Launch Tenuo and confirm it appears in the menu bar.
- Allow Accessibility access when prompted.
- Confirm the app notices the change without restarting.
- Open the editor and confirm the keyboard preview looks correct.

## Trigger behavior

- Hold Caps Lock and confirm the active layer appears.
- Press mapped keys and confirm the expected output.
- Release the trigger and confirm held outputs are released.
- Tap Caps Lock and confirm the configured tap action fires once.
- Hold a modifier trigger and confirm its normal modifier behavior remains
  available outside mapped keys.
- Try a letter key as a trigger and confirm it is consumed only while held.

## Profiles and editing

- Switch between every shipped profile.
- Add, rename, edit, duplicate, and delete a profile.
- Export a profile, import it twice, and confirm both copies are present.
- Create two layers with the same trigger and confirm the editor reports the conflict.
- Restart Tenuo and confirm settings and the active profile persist.

## Recovery

- Disable Tenuo while a trigger or mapped key is held and confirm outputs are
  released.
- Lock and unlock the Mac while a layer is active.
- Put the Mac to sleep and wake it.
- Quit Tenuo and confirm Caps Lock works normally afterwards.
- Test with Secure Input active, such as in a password field.

## Updates and release builds

- Build from source and confirm update controls are hidden with no feed URL.
- Test update checking only with a distributor-configured feed and signing key.
- For a signed build, verify the archive, notarization, stapling, and
  Gatekeeper assessment before publishing it.
