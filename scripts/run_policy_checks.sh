#!/usr/bin/env bash
set -euo pipefail

# must run inside environments/<env>
ENV_NAME="${1:-sandbox}"

# Set policy data (env-specific)
DATA_FILE="../../policy/rego/data.json"

# Generate plan + policy input
terraform init -upgrade >/dev/null
terraform plan -out tfplan >/dev/null

python ../../scripts/policy_input_from_plan.py > policy-input.json

# Install conftest locally if missing (CI installs separately)
if ! command -v conftest >/dev/null 2>&1; then
  echo "conftest not found. Install: https://www.conftest.dev/"
  exit 2
fi

# Run policy checks. --all-namespaces is required: iam.rego declares
# `package iam.guardrails`, not conftest's default `main` namespace, and
# without this flag conftest silently evaluates zero rules and exits 0
# regardless of input -- verified by reproducing this exact invocation
# against a real violation and observing "0 tests... exit code: 0".
conftest test policy-input.json -p ../../policy/rego --data "$DATA_FILE" --all-namespaces
