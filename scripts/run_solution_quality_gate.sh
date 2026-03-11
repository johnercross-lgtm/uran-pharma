#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Uran.xcodeproj"
SCHEME="Uran"

RUN_UPDATE_STRICT=false
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --update-strict)
      RUN_UPDATE_STRICT=true
      ;;
    --skip-build)
      SKIP_BUILD=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--update-strict] [--skip-build]" >&2
      exit 2
      ;;
  esac
done

if [[ "$RUN_UPDATE_STRICT" == "true" ]]; then
  "$ROOT_DIR/scripts/run_solution_breaker_gate.sh" --update-strict
fi

"$ROOT_DIR/scripts/run_solution_breaker_gate.sh" --check-strict-sync

if [[ "$SKIP_BUILD" == "false" ]]; then
  echo "[quality-gate] xcodebuild (iphonesimulator, Debug)"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Debug \
    build \
    CODE_SIGNING_ALLOWED=NO
fi

echo "[quality-gate] all checks passed"
