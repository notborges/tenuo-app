#!/bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SCHEME="Tenuo"
PROJECT="Tenuo.xcodeproj"
APP_NAME="Tenuo"
CONFIGURATION="Release"

BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DIST_DIR="dist"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

PACKAGE_FORMAT="zip"
NOTARIZE=1

for arg in "$@"; do
    case "$arg" in
        --dmg) PACKAGE_FORMAT="dmg" ;;
        --zip) PACKAGE_FORMAT="zip" ;;
        --no-notarize) NOTARIZE=0 ;;
        *) echo "error: unknown option '$arg'" >&2; exit 2 ;;
    esac
done

KEYCHAIN_PROFILE="${TENUO_KEYCHAIN_PROFILE:-tenuo-notary}"

info()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail()  { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }


info "Checking signing prerequisites"

if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    if [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
        echo "Using DEVELOPER_DIR=${DEVELOPER_DIR}"
    else
        fail "Xcode is required to archive. Install it, or run: sudo xcode-select -s /Applications/Xcode.app"
    fi
fi

if [[ -z "${TENUO_TEAM_ID:-}" && -f Local.xcconfig ]]; then
    TENUO_TEAM_ID=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' \
        Local.xcconfig | tail -1 | tr -d '[:space:]')
    [[ -n "${TENUO_TEAM_ID}" ]] && echo "Team ID read from Local.xcconfig"
fi

if [[ -z "${TENUO_TEAM_ID:-}" ]]; then
    fail "No Team ID. Either create Local.xcconfig (gitignored):
         cp Local.xcconfig.example Local.xcconfig
       and set DEVELOPMENT_TEAM in it, or pass it for this run only:
         TENUO_TEAM_ID=ABCDE12345 ./scripts/release.sh
       Your Team ID is the parenthesised value in:
         security find-identity -v -p codesigning"
fi

if [[ -n "${TENUO_SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="${TENUO_SIGN_IDENTITY}"
else
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/.*"(.*)"/\1/') || true
fi

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    fail "No 'Developer ID Application' identity in the Keychain.
       Install your certificate, then confirm with:
         security find-identity -v -p codesigning
       This script never creates, modifies, exports or revokes certificates."
fi

echo "Team:     ${TENUO_TEAM_ID}"
echo "Identity: ${SIGN_IDENTITY}"


info "Archiving"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    DEVELOPMENT_TEAM="${TENUO_TEAM_ID}" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

[[ -d "${ARCHIVE_PATH}" ]] || fail "Archive was not produced at ${ARCHIVE_PATH}"


info "Exporting signed application"

EXPORT_PLIST="${BUILD_DIR}/ExportOptions-resolved.plist"
cp scripts/ExportOptions.plist "${EXPORT_PLIST}"
/usr/libexec/PlistBuddy -c "Add :teamID string ${TENUO_TEAM_ID}" "${EXPORT_PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :teamID ${TENUO_TEAM_ID}" "${EXPORT_PLIST}"

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_PLIST}"

[[ -d "${APP_PATH}" ]] || fail "Export did not produce ${APP_PATH}"

info "Verifying signature before packaging"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

SIGNATURE=$(codesign --display --verbose=4 "${APP_PATH}" 2>&1 || true)

echo "${SIGNATURE}" | grep -E "Identifier|Authority|TeamIdentifier|Runtime|Timestamp" || true

if [[ "${SIGNATURE}" != *"(runtime)"* ]]; then
    fail "Hardened Runtime is not enabled on the exported app."
fi

if [[ "${SIGNATURE}" == *"adhoc"* ]]; then
    fail "App is ad-hoc signed. Set CODE_SIGN_IDENTITY in Local.xcconfig to a Developer ID identity."
fi


VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")

if [[ "${PACKAGE_FORMAT}" == "dmg" ]]; then
    PACKAGE_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    info "Creating ${PACKAGE_PATH}"
    rm -f "${PACKAGE_PATH}"
    STAGING="${BUILD_DIR}/dmg-staging"
    rm -rf "${STAGING}"
    mkdir -p "${STAGING}"
    cp -R "${APP_PATH}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" \
        -ov -format UDZO "${PACKAGE_PATH}"
    codesign --sign "${SIGN_IDENTITY}" --timestamp "${PACKAGE_PATH}"
else
    PACKAGE_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"
    info "Creating ${PACKAGE_PATH}"
    rm -f "${PACKAGE_PATH}"
    ditto -c -k --keepParent "${APP_PATH}" "${PACKAGE_PATH}"
fi

if [[ "${NOTARIZE}" -eq 0 ]]; then
    info "Skipping notarization (--no-notarize)"
    echo "Signed but un-notarized package: ${PACKAGE_PATH}"
    exit 0
fi


info "Submitting to notarization service"
echo "Using Keychain profile '${KEYCHAIN_PROFILE}'"

if ! xcrun notarytool submit "${PACKAGE_PATH}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait; then
    echo
    echo "Notarization failed. Fetch the detailed log with:" >&2
    echo "  xcrun notarytool history --keychain-profile ${KEYCHAIN_PROFILE}" >&2
    echo "  xcrun notarytool log <submission-id> --keychain-profile ${KEYCHAIN_PROFILE}" >&2
    exit 1
fi


info "Stapling the ticket"
if [[ "${PACKAGE_FORMAT}" == "dmg" ]]; then
    xcrun stapler staple "${PACKAGE_PATH}"
else
    xcrun stapler staple "${APP_PATH}"
    rm -f "${PACKAGE_PATH}"
    ditto -c -k --keepParent "${APP_PATH}" "${PACKAGE_PATH}"
fi


info "Validating"

echo "--- stapler validate ---"
xcrun stapler validate "${APP_PATH}"

echo "--- codesign ---"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "--- spctl (Gatekeeper) ---"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

if [[ "${PACKAGE_FORMAT}" == "dmg" ]]; then
    echo "--- spctl on the disk image ---"
    spctl --assess --type open --context context:primary-signature --verbose=4 "${PACKAGE_PATH}"
fi

info "Done"
echo "Distributable: ${PACKAGE_PATH}"
echo "Version:       ${VERSION}"
