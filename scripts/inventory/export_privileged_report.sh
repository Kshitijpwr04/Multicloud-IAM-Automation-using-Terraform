#!/usr/bin/env bash
set -euo pipefail

ENV_DIR="${1:-environments/sandbox}"
OUT_DIR="${2:-evidence/inventory}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUT_DIR"

pushd "$ENV_DIR" >/dev/null
terraform show -json > tfstate.json
popd >/dev/null

python3 - <<PYTHON
import json
import datetime

with open(f"{ENV_DIR}/tfstate.json") as f:
    state = json.load(f)

privileged = []

for res in state.get("values", {}).get("root_module", {}).get("resources", []):
    rtype = res.get("type")
    values = res.get("values", {})

    # Azure privileged roles
    if rtype == "azurerm_role_assignment":
        role = str(values.get("role_definition_name", "")).lower()
        if role in ["owner", "contributor"]:
            privileged.append({
                "cloud": "Azure",
                "role": values.get("role_definition_name"),
                "principal": values.get("principal_id"),
                "scope": values.get("scope")
            })

    # AWS privileged policies
    if rtype == "aws_iam_role_policy_attachment":
        arn = str(values.get("policy_arn", ""))
        if "AdministratorAccess" in arn:
            privileged.append({
                "cloud": "AWS",
                "role": "AdministratorAccess",
                "principal": values.get("role")
            })

    # GCP privileged roles
    if rtype == "google_project_iam_binding":
        role = str(values.get("role", "")).lower()
        if role in ["roles/owner", "roles/editor"]:
            privileged.append({
                "cloud": "GCP",
                "role": values.get("role"),
                "project": values.get("project")
            })

out_file = f"{OUT_DIR}/privileged-report-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.json"

with open(out_file, "w") as f:
    json.dump(privileged, f, indent=2)

print("Wrote:", out_file)
PYTHON

rm "${ENV_DIR}/tfstate.json"
