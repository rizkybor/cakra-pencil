#!/usr/bin/env bash
# Builds the iPad installer: OCCA-<version>.ipa, signed for Ad Hoc distribution (Apple calls it "Release Testing"),
# ready to upload in HRIS (License Manager › OCCA › Versions › iPad installer) and install over the air through a
# single-use install link.
#
#   Tools/make-ipa.sh           # archive + export the Ad Hoc .ipa
#   Tools/make-ipa.sh --check   # only check the prerequisites (certificate, team), build nothing
#
# Needs the paid Apple Developer Program: Ad Hoc builds are signed with an "Apple Distribution" certificate and a
# provisioning profile that lists every iPad (UDID) allowed to install the build. A Personal Team cannot do this.
#
# One-time setup (see README › iPad installer):
#   1. Join the Apple Developer Program with the team below.
#   2. Xcode › Settings › Accounts › Manage Certificates › + › Apple Distribution.
#   3. Register each client iPad: Apple Developer › Certificates, Identifiers & Profiles › Devices › + (UDID).
#      Xcode puts the registered iPads in the Ad Hoc profile on the next build (-allowProvisioningUpdates).
#
# Environment:
#   TEAM_ID              Apple Developer Team ID (default: A9ZMBW5H8D)
#   ALLOW_CLOUD_SIGNING  1 = continue without a local Apple Distribution certificate (Xcode cloud-managed signing;
#                        needs an Admin role in the team)
#
# Output: build/release/OCCA-<version>.ipa and its SHA-256 (compare with the one HRIS shows after the upload).

set -euo pipefail

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
WORK="$OUT/ipa-work"
ARCHIVE="$WORK/OCCA-iOS.xcarchive"
EXPORT="$WORK/export"
SCHEME="CakraPencil"
DESTINATION="generic/platform=iOS"
TEAM_ID="${TEAM_ID:-A9ZMBW5H8D}"
BUNDLE_ID="id.cakrapencil.app"

needs_paid_team() {
  cat >&2 <<MSG

An Ad Hoc .ipa needs the paid Apple Developer Program (team $TEAM_ID).
  - Ad Hoc builds are signed with an "Apple Distribution" certificate and a provisioning profile that lists the
    iPads (UDIDs) allowed to install them. A Personal Team (free account) cannot create either.
  - After joining: Xcode › Settings › Accounts › Manage Certificates › + › Apple Distribution, register the client
    iPads in Apple Developer › Devices, then run Tools/make-ipa.sh again.
MSG
  [[ -n "${1:-}" ]] && echo "  ($1)" >&2
  exit 1
}

cd "$ROOT"
SETTINGS="$(xcodebuild -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" -showBuildSettings 2>/dev/null || true)"
VERSION="$(awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }' <<<"$SETTINGS")"
BUILD="$(awk -F' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }' <<<"$SETTINGS")"
if [[ -z "$VERSION" ]]; then
  echo "Could not read MARKETING_VERSION from the $SCHEME scheme." >&2
  exit 1
fi
IPA="$OUT/OCCA-$VERSION.ipa"

# Xcode 15.3 renamed the export method "ad-hoc" to "release-testing".
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
IFS=. read -r XC_MAJOR XC_MINOR _ <<<"${XCODE_VERSION}.0.0"
if (( XC_MAJOR > 15 || (XC_MAJOR == 15 && XC_MINOR >= 3) )); then
  METHOD="release-testing"
else
  METHOD="ad-hoc"
fi
echo "OCCA $VERSION ($BUILD) for iPad · team $TEAM_ID · Xcode $XCODE_VERSION · export method $METHOD"

# Distribution certificate first, so a Personal Team stops before anything is built.
DIST_ID="$(security find-identity -v -p codesigning | awk -F'"' '/"(Apple|iPhone) Distribution/ { print $2; exit }')"
if [[ -z "$DIST_ID" ]]; then
  if [[ "${ALLOW_CLOUD_SIGNING:-0}" != "1" ]]; then
    needs_paid_team "No \"Apple Distribution\" certificate in the Keychain. With cloud-managed signing, set ALLOW_CLOUD_SIGNING=1."
  fi
  echo "No local Apple Distribution certificate; relying on Xcode cloud-managed signing."
else
  echo "Distribution certificate: $DIST_ID"
fi

if (( CHECK_ONLY )); then
  echo "Prerequisites OK. Run without --check to build $IPA."
  exit 0
fi

# Only this script's own files are replaced; a .dmg next to it stays.
rm -rf "${WORK:?}" "${IPA:?}"
mkdir -p "$WORK"

xcodebuild archive -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates -quiet

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST

EXPORT_LOG="$WORK/export.log"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates >"$EXPORT_LOG" 2>&1; then
  grep -E "error|Error" "$EXPORT_LOG" | tail -5 >&2 || true
  if grep -qiE "personal (development )?team|not a member|developer program|no (signing certificate|profiles?)|requires a provisioning profile|doesn't (include|support)|no devices|ad-?hoc|release-testing" "$EXPORT_LOG"; then
    needs_paid_team "xcodebuild -exportArchive failed; full log: $EXPORT_LOG"
  fi
  echo "Export failed; full log: $EXPORT_LOG" >&2
  exit 1
fi

EXPORTED="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -1)"
if [[ -z "$EXPORTED" ]]; then
  echo "The export produced no .ipa (see $EXPORT)." >&2
  exit 1
fi
mv "$EXPORTED" "$IPA"

# Check what HRIS will check: bundle id and version in Payload/*.app/Info.plist; show the profile's iPads.
INSPECT="$WORK/inspect"
mkdir -p "$INSPECT"
unzip -q "$IPA" 'Payload/*.app/Info.plist' 'Payload/*.app/embedded.mobileprovision' -d "$INSPECT"
APP_DIR="$(find "$INSPECT/Payload" -maxdepth 1 -name '*.app' | head -1)"
IPA_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Info.plist")"
IPA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Info.plist")"
if [[ "$IPA_BUNDLE" != "$BUNDLE_ID" || "$IPA_VERSION" != "$VERSION" ]]; then
  echo "Unexpected app in the .ipa: $IPA_BUNDLE $IPA_VERSION (expected $BUNDLE_ID $VERSION)." >&2
  exit 1
fi
if [[ -f "$APP_DIR/embedded.mobileprovision" ]]; then
  security cms -D -i "$APP_DIR/embedded.mobileprovision" >"$WORK/profile.plist" 2>/dev/null
  PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK/profile.plist" 2>/dev/null || echo '?')"
  PROFILE_EXPIRES="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$WORK/profile.plist" 2>/dev/null || echo '?')"
  DEVICES="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$WORK/profile.plist" 2>/dev/null | grep -cE '^\s+[0-9A-Fa-f-]{20,}$' || true)"
fi

# Keep only the installer.
rm -rf "${WORK:?}"

echo
echo "Installer: $IPA"
echo "Size:      $(du -h "$IPA" | cut -f1)"
echo "SHA-256:   $(shasum -a 256 "$IPA" | cut -d' ' -f1)"
[[ -n "${PROFILE_NAME:-}" ]] && echo "Profile:   $PROFILE_NAME · $DEVICES iPad(s) · expires $PROFILE_EXPIRES"
echo "Upload it in HRIS › License Manager › OCCA › Versions › $VERSION › iPad installer, then make an install link per iPad."
