#!/bin/bash
# Runs the benchmarks on the VM, Chrome (JS) and Chrome (Wasm), printing the
# Markdown tables for `benchmark/HISTORY.md`.
#
# Usage: ./benchmark/run.sh [vm] [js] [wasm]   (default: all)

set -e

cd "$(dirname "$0")/.."

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(vm js wasm)
fi

for target in "${TARGETS[@]}"; do
  case "$target" in
    vm) args=(-p vm) ;;
    js) args=(-p chrome) ;;
    wasm) args=(-p chrome -c dart2wasm) ;;
    *) echo "Unknown target: $target" >&2; exit 1 ;;
  esac

  dart test benchmark/mercury_client_benchmark.dart "${args[@]}" -r expanded \
    | grep -E '^\||^## '
done
