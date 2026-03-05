#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

LOCK_DIR="$ROOT_DIR/.run-menubar.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Launcher already running. Try again in a few seconds."
  exit 1
fi
trap 'rmdir "$LOCK_DIR"' EXIT

if pgrep -x "CodexAudioMonitor" >/dev/null 2>&1; then
  echo "Restarting existing CodexAudioMonitor instance..."
  pkill -x "CodexAudioMonitor" || true
  for _ in {1..20}; do
    if ! pgrep -x "CodexAudioMonitor" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/CodexAudioMonitor.app"

echo "Building CodexAudioMonitorApp..."
xcodebuild \
  -project "$ROOT_DIR/CodexAudioMonitor.xcodeproj" \
  -scheme CodexAudioMonitorApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found at: $APP_PATH"
  exit 1
fi

echo "Launching CodexAudioMonitor..."
open "$APP_PATH"
