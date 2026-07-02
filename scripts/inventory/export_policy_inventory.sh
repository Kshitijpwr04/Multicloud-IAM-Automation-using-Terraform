#!/usr/bin/env bash
set -euo pipefail

ENV_DIR="${1:-environments/sandbox}"
OUT_DIR="${2:-evidence/inventory}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUT_DIR"

pushd "$ENV_DIR" >/dev/null
terraform plan -out "tfplan-${TS}" >/dev/null
terraform show -json "tfplan-${TS}" > "../../${OUT_DIR}/tfplan-${TS}.json"
python3 ../../scripts/policy_input_from_plan.py "../../${OUT_DIR}/tfplan-${TS}.json" > "../../${OUT_DIR}/policy-input-${TS}.json"
popd >/dev/null

echo "Wrote:"
echo "  ${OUT_DIR}/tfplan-${TS}.json"
echo "  ${OUT_DIR}/policy-input-${TS}.json"
