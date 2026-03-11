#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_PATH="$ROOT_DIR/Uran/URAN_Pharma_Engine"
BREAKER_PATH="$BASE_PATH/tests/RECIPE_BREAKER_TEST_SET.json"
SNAPSHOT_PATH="$BASE_PATH/tests/RECIPE_BREAKER_STRICT_SNAPSHOTS.json"
BUILD_DIR="${TMPDIR:-/tmp}/uran_solution_breaker_gate"

mkdir -p "$BUILD_DIR"

UPDATE_STRICT=false
CHECK_STRICT_SYNC=false

for arg in "$@"; do
  case "$arg" in
    --update-strict)
      UPDATE_STRICT=true
      ;;
    --check-strict-sync)
      CHECK_STRICT_SYNC=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--update-strict] [--check-strict-sync]" >&2
      exit 2
      ;;
  esac
done

COMMON_SOURCES=(
  "$ROOT_DIR/Uran/RxEngine/SolutionEngine/SolutionEngineTypes.swift"
  "$ROOT_DIR/Uran/RxEngine/SolutionEngine/SolutionEngineReferences.swift"
  "$ROOT_DIR/Uran/RxEngine/SolutionEngine/SolutionEngineModules.swift"
  "$ROOT_DIR/Uran/RxEngine/SolutionEngine/SolutionEngineOrchestrator.swift"
  "$ROOT_DIR/Uran/RxEngine/SolutionEngine/RxReasoningSkeleton.swift"
  "$ROOT_DIR/Uran/RxEngine/Core/WaterSolubilityHeuristics.swift"
  "$ROOT_DIR/Uran/SubstancePropertyCatalog.swift"
  "$ROOT_DIR/scripts/solution_runner_shims.swift"
)

build_runner() {
  local entry="$1"
  local output="$2"
  # Keep CI stable across Xcode/Swift versions: no optimizer required for gate binaries.
  swiftc -Onone -parse-as-library "$entry" "${COMMON_SOURCES[@]}" -o "$output"
}

run_update_strict() {
  echo "[breaker-gate] rebuilding strict snapshots"
  build_runner "$ROOT_DIR/scripts/update_solution_breaker_strict_snapshots.swift" "$BUILD_DIR/update_strict"
}

if [[ "$UPDATE_STRICT" == "true" ]]; then
  run_update_strict
  "$BUILD_DIR/update_strict" "$BASE_PATH" "$BREAKER_PATH" "$SNAPSHOT_PATH"
fi

if [[ "$CHECK_STRICT_SYNC" == "true" ]]; then
  run_update_strict
  tmp_snapshot="$(mktemp "${TMPDIR:-/tmp}/strict_snapshots.XXXXXX")"
  cp "$SNAPSHOT_PATH" "$tmp_snapshot"
  "$BUILD_DIR/update_strict" "$BASE_PATH" "$BREAKER_PATH" "$tmp_snapshot"
  if ! cmp -s "$SNAPSHOT_PATH" "$tmp_snapshot"; then
    echo "[breaker-gate] strict snapshots are stale; regenerate with:" >&2
    echo "  scripts/run_solution_breaker_gate.sh --update-strict" >&2
    echo "[breaker-gate] diff preview:" >&2
    diff -u "$SNAPSHOT_PATH" "$tmp_snapshot" | sed -n '1,160p' >&2 || true
    rm -f "$tmp_snapshot"
    exit 3
  fi
  rm -f "$tmp_snapshot"
fi

echo "[breaker-gate] running base breaker set"
build_runner "$ROOT_DIR/scripts/run_solution_breaker_tests.swift" "$BUILD_DIR/run_breaker"
"$BUILD_DIR/run_breaker" "$BASE_PATH" "$BREAKER_PATH"

echo "[breaker-gate] running strict snapshots"
build_runner "$ROOT_DIR/scripts/run_solution_breaker_snapshot_tests.swift" "$BUILD_DIR/run_snapshot"
"$BUILD_DIR/run_snapshot" "$BASE_PATH" "$BREAKER_PATH" "$SNAPSHOT_PATH"

echo "[breaker-gate] all checks passed"
