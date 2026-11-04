#!/bin/bash
set -euo pipefail
regtest_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$regtest_dir/../.." && pwd)"
compose=(docker compose -f "$regtest_dir/compose.yaml")

# This project creates disposable regtest containers only. Refuse to reuse a run.
if [[ -n "$("${compose[@]}" ps -aq)" ]]; then
  echo "Existing cashuswift-onchain-regtest containers found. Remove them before running." >&2
  exit 1
fi
cleanup() { "${compose[@]}" down --volumes; }
trap cleanup EXIT
"${compose[@]}" up -d --wait --wait-timeout 90
cd "$repo_dir"
CASHUSWIFT_ONCHAIN_REGTEST=1 swift test --filter OnchainRegtestTests
