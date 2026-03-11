#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/Uran.xcodeproj"
SCHEME="Uran"
APP_BUNDLE_ID="com.eugen.Uran"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Uran-eledvhumuqvrpdcznsokmkdmmlsi"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Uran.app"

log() {
  printf '[rx-smoke] %s\n' "$*"
}

booted_udid="$(xcrun simctl list devices | awk -F '[()]' '/Booted/ {print $2; exit}')"
if [[ -z "$booted_udid" ]]; then
  target_udid="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [[ -z "$target_udid" ]]; then
    echo "No available iPhone simulator found" >&2
    exit 2
  fi
  log "Booting simulator $target_udid"
  xcrun simctl boot "$target_udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$target_udid" -b
  DEVICE="$target_udid"
else
  DEVICE="$booted_udid"
fi

log "Building app"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator -configuration Debug build >/tmp/rx_smoke_build.log

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 3
fi

log "Installing app"
xcrun simctl terminate "$DEVICE" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$DEVICE" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH" >/dev/null

log "Launching with strict smoke"
xcrun simctl launch "$DEVICE" "$APP_BUNDLE_ID" -rx-smoke-force -rx-smoke-strict >/tmp/rx_smoke_launch.log

DATA_DIR="$(xcrun simctl get_app_container "$DEVICE" "$APP_BUNDLE_ID" data)"
REPORT_JSON="$DATA_DIR/Library/Caches/rx_smoke_report.json"

deadline=$((SECONDS + 45))
while [[ $SECONDS -lt $deadline ]]; do
  if [[ -f "$REPORT_JSON" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -f "$REPORT_JSON" ]]; then
  echo "Smoke report was not generated in time: $REPORT_JSON" >&2
  exit 4
fi

generated_at="$(/usr/bin/plutil -extract generatedAt raw -o - "$REPORT_JSON" 2>/dev/null || echo "")"
passed="$(/usr/bin/plutil -extract passed raw -o - "$REPORT_JSON" 2>/dev/null || echo false)"
failed="$(/usr/bin/plutil -extract failed raw -o - "$REPORT_JSON" 2>/dev/null || echo -1)"
total="$(/usr/bin/plutil -extract total raw -o - "$REPORT_JSON" 2>/dev/null || echo -1)"

log "Result: passed=$passed failed=$failed total=$total at=$generated_at"
log "Report: $REPORT_JSON"

if [[ "$passed" != "true" || "$failed" != "0" ]]; then
  log "Failed scenarios payload:"
  /usr/bin/plutil -extract failedScenarios json -o - "$REPORT_JSON" 2>/dev/null || cat "$REPORT_JSON"
  exit 1
fi

exit 0
