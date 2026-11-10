#!/usr/bin/env bash
# Builds the Mac installer: OCCA-<version>.dmg, signed with Developer ID and notarized by Apple, ready to upload in
# HRIS (License Manager › OCCA › Versions).
#
#   Tools/make-dmg.sh                 # Developer ID + notarization (for clients)
#   Tools/make-dmg.sh --no-notarize   # Developer ID, not notarized (quick check; clients' Macs will block it)
#   Tools/make-dmg.sh --local         # ad-hoc signed, only for this Mac (tests the packaging, never for clients)
#
# One-time setup (see README › Mac installer):
#   1. Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application.
#   2. xcrun notarytool store-credentials occa-notary --apple-id <Apple ID> --team-id <TEAM_ID>
#      (asks for an app-specific password from appleid.apple.com; stored in the Keychain).
#
# Environment:
#   TEAM_ID         Apple Developer Team ID (default: taken from the Developer ID certificate)
#   NOTARY_PROFILE  notarytool keychain profile (default: occa-notary)
#
# Output: build/release/OCCA-<version>.dmg and its SHA-256 (compare with the one HRIS shows after the upload).

set -euo pipefail

MODE="release"
case "${1:-}" in
  --no-notarize) MODE="signed" ;;
  --local) MODE="local" ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/OCCA.xcarchive"
EXPORT="$OUT/export"
STAGING="$OUT/dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-occa-notary}"
SCHEME="CakraPencil"
DESTINATION="generic/platform=macOS,variant=Mac Catalyst"

cd "$ROOT"
VERSION="$(xcodebuild -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')"
BUILD="$(xcodebuild -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }')"
DMG="$OUT/OCCA-$VERSION.dmg"
echo "OCCA $VERSION ($BUILD) · mode: $MODE"

# Developer ID certificate first, so a missing one stops before anything is built or removed.
if [[ "$MODE" != "local" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
  if [[ -z "$SIGN_ID" ]]; then
    echo "No \"Developer ID Application\" certificate in the Keychain." >&2
    echo "Create it in Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application." >&2
    exit 1
  fi
  if [[ "$MODE" == "release" ]] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarytool profile \"$NOTARY_PROFILE\". Run once:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <TEAM_ID>" >&2
    exit 1
  fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"

if [[ "$MODE" == "local" ]]; then
  # Ad-hoc: the packaging only. Gatekeeper blocks this on any other Mac.
  xcodebuild build -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" \
    -derivedDataPath "$OUT/DerivedData" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet
  mkdir -p "$EXPORT"
  ditto "$OUT/DerivedData/Build/Products/Release-maccatalyst/OCCA.app" "$EXPORT/OCCA.app"
  SIGN_ID="-"
else
  TEAM_ID="${TEAM_ID:-$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$SIGN_ID")}"
  echo "Signing as: $SIGN_ID (team $TEAM_ID)"

  # Archive with the hardened runtime (required for notarization), then export for Developer ID.
  xcodebuild archive -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" \
    -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$TEAM_ID" ENABLE_HARDENED_RUNTIME=YES \
    -allowProvisioningUpdates -quiet

  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
fi

APP="$EXPORT/OCCA.app"
codesign --verify --deep --strict "$APP"

# Disk image: the app and a shortcut to Applications, so installing is one drag.
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/OCCA.app"
ln -s /Applications "$STAGING/Applications"
if [[ "$MODE" != "release" ]]; then
  # Not notarized: macOS blocks the first launch; tell testers how to open it.
  cat > "$STAGING/How to open OCCA.txt" <<'TXT'
OCCA test build (not notarized by Apple)

1. Drag OCCA into Applications.
2. Open OCCA. macOS says it cannot verify the app: click Done (not Move to Trash).
3. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to OCCA.
   Enter your Mac password, then click Open.
4. After an update, repeat steps 2-3. If OCCA asks for your license key again, enter it again.

Only for testing. Release versions from Jendela Cakra Digital open without these steps.

---

Cara membuka OCCA (versi uji, belum dinotarisasi Apple)

1. Seret OCCA ke folder Applications.
2. Buka OCCA. macOS bilang tidak bisa memverifikasi aplikasi: klik Done (jangan Move to Trash).
3. Buka System Settings > Privacy & Security, gulir ke bawah, klik "Open Anyway" di samping OCCA.
   Masukkan password Mac, lalu klik Open.
4. Setelah update, ulangi langkah 2-3. Kalau OCCA meminta license key lagi, masukkan lagi.
TXT
fi
hdiutil create -volname "OCCA $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"
codesign --force --sign "$SIGN_ID" "$DMG"

if [[ "$MODE" == "release" ]]; then
  echo "Notarizing (a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

# Keep only the installer.
rm -rf "$ARCHIVE" "$EXPORT" "$OUT/DerivedData" "$OUT/ExportOptions.plist"

echo
echo "Installer: $DMG"
echo "Size:      $(du -h "$DMG" | cut -f1)"
echo "SHA-256:   $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
[[ "$MODE" == "release" ]] && echo "Upload it in HRIS › License Manager › OCCA › Versions › $VERSION." || echo "Not notarized: for testing only."
