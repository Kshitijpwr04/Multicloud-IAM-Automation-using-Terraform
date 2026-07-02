# CLAUDE.md — Project Context for Claude Code

This file is read automatically at the start of every Claude Code session in this repo.
Do not delete it; update it as the project evolves (especially the "Current Status" section).

## Project

Multi-Cloud IAM Automation using Terraform — a GitOps-driven, persona-based IAM governance
platform across Azure, AWS, and GCP.

## Core design principles (do not violate these without asking first)

- **Persona abstraction**: users get access through personas (security_analyst, cloud_engineer,
  auditor, devsecops_engineer, break_glass), never through direct per-user role assignments.
- **YAML is the source of truth** for identities (`identities/users.yaml`) and personas
  (`identities/personas.yaml`). Terraform reads from these, not the other way around.
- **Least privilege by default.** Any new permission grant should default to read-only /
  minimal scope unless the persona explicitly requires more.
- **Break-glass is isolated.** Emergency access (`break_glass` persona) must never be
  assignable via a normal mover/joiner request — this is already enforced in
  `scripts/validate_requests.py` and must stay enforced in any new logic (e.g. OPA policies).
- **Git is the control plane.** Access changes happen via PRs against
  `identities/access-requests/{joiner,mover,leaver}/`, validated in CI before merge.
- **Evidence generation matters.** Anything that changes access should be traceable —
  don't bypass the evidence-export scripts in `scripts/inventory/`.

## Tech stack

Terraform (azurerm ~>4.0, aws ~>5.0, google ~>5.0, msgraph ~>0.3), YAML, Python (validation
scripts), OPA/Conftest (policy-as-code — see rebuild plan, this is currently unimplemented),
GitHub Actions.

## Current status (read `IAM_Project_Rebuild_Plan.md` in this repo root for full detail)

As of the last audit:
- **Solid and working**: Azure module (Entra ID groups, RBAC, break-glass isolation),
  AWS module (roles + policy attachment, though permission boundary is a placeholder),
  `identities/*.yaml`, `scripts/validate_requests.py`, evidence-export shell scripts,
  the CI validation workflow.
- **Broken / needs fixing**: `modules/gcp-iam` is empty but referenced by
  `environments/sandbox/main.tf` (terraform plan currently fails). Real Azure
  subscription/tenant IDs are hardcoded as defaults in `environments/sandbox/variables.tf`
  (security hygiene issue — fix before anything else). `scripts/inventory/export_policy_inventory.sh`
  calls `scripts/policy_input_from_plan.py`, which doesn't exist.
- **Not yet implemented**: `policy/opa/` and `policy/conftest/` are empty — no actual
  policy-as-code exists yet despite being a core part of the project's value proposition.
  `.github/CODEOWNERS` and PR template don't exist. All files in `/docs` are empty stubs.
  `environments/dev` and `environments/prod` are empty — only `sandbox` is populated.

**Work through `IAM_Project_Rebuild_Plan.md` phase by phase, in order.** Don't skip Phase 0
(security hygiene). Update the checkboxes in that file as phases complete, and update the
"Current status" section above so future sessions (and I, reading this file) stay accurate.

## How to work in this repo

- Before making changes, briefly state what you're about to do and why.
- After making changes, **run the actual validation** (`terraform validate`, `terraform plan`,
  `conftest test`, or `python scripts/validate_requests.py` as appropriate) and show the output.
  Never claim something works without having run it.
- If existing code contradicts the rebuild plan, flag it — don't silently resolve the conflict.
- Keep commits small and scoped to one rebuild-plan checklist item where possible.
- Don't reintroduce hardcoded credentials, subscription IDs, or tenant IDs as defaults —
  use `terraform.tfvars` (gitignored) instead.
