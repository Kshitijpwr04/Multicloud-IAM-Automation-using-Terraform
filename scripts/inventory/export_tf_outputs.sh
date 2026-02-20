#!/usr/bin/env bash
set -euo pipefail

ENV_DIR="${1:-environments/sandbox}"
OUT_DIR="${2:-evidence/inventory}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUT_DIR"

pushd "$ENV_DIR" >/dev/null
terraform output -json > "../../${OUT_DIR}/tf-outputs-${TS}.json"
popd >/dev/null

echo "Wrote: ${OUT_DIR}/tf-outputs-${TS}.json"
