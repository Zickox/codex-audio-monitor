#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CodexAudioMonitor.xcodeproj"
SCHEME="CodexAudioMonitorApp"
CONFIGURATION="Release"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/dist/release}"
ARCHIVE_PATH="$ARTIFACTS_DIR/CodexAudioMonitor.xcarchive"
EXPORT_PATH="$ARTIFACTS_DIR/export"
STAGING_PATH="$ARTIFACTS_DIR/dmg-staging"
DMG_PATH="$ARTIFACTS_DIR/CodexAudioMonitor.dmg"
ZIP_PATH="$ARTIFACTS_DIR/CodexAudioMonitor.zip"
EXPORT_OPTIONS_TEMPLATE="$ROOT_DIR/scripts/ExportOptions-DeveloperID.plist.template"

TEAM_ID="${TEAM_ID:-}"
ASC_PROFILE="${ASC_PROFILE:-}"
NOTARIZE=1
CREATE_DMG=1
SKIP_STAPLE=0

usage() {
  cat <<'EOF'
Build a signed macOS release and optionally notarize it with Apple.

Usage:
  scripts/release-macos.sh --team-id TEAMID [--profile ASC_PROFILE] [--skip-notarize] [--skip-dmg] [--skip-staple]

Options:
  --team-id TEAMID     Apple Developer Team ID used for Developer ID export.
  --profile NAME       Optional asc auth profile.
  --skip-notarize      Skip asc notarization submit.
  --skip-dmg           Skip DMG creation and notarize the ZIP instead.
  --skip-staple        Skip stapling after notarization.
  --help               Show this help.

Environment overrides:
  ARTIFACTS_DIR        Output directory. Default: dist/release
  TEAM_ID              Same as --team-id
  ASC_PROFILE          Same as --profile
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --profile)
      ASC_PROFILE="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      NOTARIZE=0
      shift
      ;;
    --skip-dmg)
      CREATE_DMG=0
      shift
      ;;
    --skip-staple)
      SKIP_STAPLE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

require_tool xcodebuild
require_tool security
require_tool ditto
require_tool hdiutil
require_tool xcrun

if [[ -z "$TEAM_ID" ]]; then
  echo "--team-id is required." >&2
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Xcode project not found: $PROJECT_PATH" >&2
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS_TEMPLATE" ]]; then
  echo "ExportOptions template not found: $EXPORT_OPTIONS_TEMPLATE" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No 'Developer ID Application' signing identity found in keychain." >&2
  exit 1
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  require_tool asc
  ASC_ARGS=()
  if [[ -n "$ASC_PROFILE" ]]; then
    ASC_ARGS+=(--profile "$ASC_PROFILE")
  fi
  asc "${ASC_ARGS[@]}" notarization submit --help >/dev/null
fi

rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

EXPORT_OPTIONS_PLIST="$ARTIFACTS_DIR/ExportOptions-DeveloperID.plist"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$EXPORT_OPTIONS_TEMPLATE" > "$EXPORT_OPTIONS_PLIST"

echo "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS"

echo "Exporting signed app..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_PATH/CodexAudioMonitor.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Exported app bundle not found: $APP_PATH" >&2
  exit 1
fi

echo "Verifying Developer ID signature..."
CODESIGN_INFO="$(codesign -dvvv "$APP_PATH" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$CODESIGN_INFO"
grep -q "Timestamp=" <<<"$CODESIGN_INFO"

echo "Creating ZIP payload..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

NOTARIZATION_TARGET="$ZIP_PATH"
if [[ "$CREATE_DMG" -eq 1 ]]; then
  echo "Creating DMG..."
  rm -rf "$STAGING_PATH"
  mkdir -p "$STAGING_PATH"
  ditto "$APP_PATH" "$STAGING_PATH/CodexAudioMonitor.app"
  ln -s /Applications "$STAGING_PATH/Applications"
  hdiutil create \
    -volname "Codex Audio Monitor" \
    -srcfolder "$STAGING_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  NOTARIZATION_TARGET="$DMG_PATH"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "Submitting for notarization..."
  asc "${ASC_ARGS[@]}" notarization submit \
    --file "$NOTARIZATION_TARGET" \
    --wait \
    --output table

  if [[ "$SKIP_STAPLE" -eq 0 ]]; then
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
    if [[ "$CREATE_DMG" -eq 1 ]]; then
      xcrun stapler staple "$DMG_PATH"
    fi
  fi
fi

if [[ -f "$ZIP_PATH" ]]; then
  shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
fi

if [[ -f "$DMG_PATH" ]]; then
  shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
fi

echo
echo "Release artifacts:"
echo "  App: $APP_PATH"
echo "  ZIP: $ZIP_PATH"
if [[ "$CREATE_DMG" -eq 1 ]]; then
  echo "  DMG: $DMG_PATH"
fi
