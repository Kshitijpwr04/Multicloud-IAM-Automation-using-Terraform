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

As of Phase 0 completion (2026-07-02):
- **Solid and working**: Azure module (Entra ID groups, RBAC, break-glass isolation),
  AWS module (roles + policy attachment; break-glass gets a short 900s session duration;
  permission boundary is still a placeholder), GCP module (service accounts + persona-based
  `google_project_iam_member` bindings — at code parity with aws-iam/azure-iam, but gated
  off by default via `enable_gcp` and not yet validated against a real GCP project — still
  uses a `CHANGE_ME_GCP_PROJECT_ID` placeholder), `identities/*.yaml`,
  `scripts/validate_requests.py` (break_glass blocked on both joiner and mover paths),
  evidence-export shell scripts, the CI validation workflow, `.github/CODEOWNERS` and PR
  template.
- **Fixed this session (Phase 0)**: hardcoded real-looking Azure subscription/tenant ID
  defaults removed from `environments/sandbox/variables.tf` (now required vars, no default —
  set via a local, gitignored `terraform.tfvars`). `.gitignore` now covers
  `terraform.tfvars`/`*.auto.tfvars` and local plan/state artifacts (`tfplan*`,
  `tfstate.json`, `policy-input.json`). `scripts/policy_input_from_plan.py` now accepts an
  explicit plan-JSON path so `scripts/inventory/export_policy_inventory.sh` no longer silently
  reads stale plan data.
  **Known exposure, not remediated**: those two real-looking IDs are still present in git
  history (introduced at commit `b02b597`) and embedded in ~18 already-committed evidence
  JSON files under `evidence/demo/` and `evidence/inventory/`. Rotating a sandbox
  tenant/subscription ID usually isn't necessary — flagging for awareness. Regenerating the
  evidence artifacts is Phase 6 work.
- **Partially implemented**: `policy/rego/iam.rego` + `data.json` + `break-glass-allowlist.json`
  already implement real guardrail rules (deny Azure `Owner`, deny AWS `AdministratorAccess`,
  deny `break_glass` via joiner/mover) and `.github/workflows/policy-ci.yml` already runs them
  via `scripts/run_policy_checks.sh` + conftest in CI. Still missing: `policy/opa/` and
  `policy/conftest/` are empty (`.gitkeep` only) — no Conftest *test cases* proving the
  guardrails actually catch violations yet (the "tests are what make this credible" part of
  Phase 3).
- **Not yet implemented**: All files in `/docs` are empty stubs. `environments/dev` and
  `environments/prod` are empty — only `sandbox` is populated.

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
