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
scripts), OPA/Conftest (policy-as-code — implemented with a test suite as of Phase 3, see
Current status below), GitHub Actions.

## Current status (read `IAM_Project_Rebuild_Plan.md` in this repo root for full detail)

As of Phase 4 in progress:
- **Phase 0 (security hygiene) — done.** Hardcoded Azure subscription/tenant ID defaults
  removed; `.gitignore` covers `terraform.tfvars`, local plan/state artifacts, `__pycache__/`;
  `policy_input_from_plan.py`/`export_policy_inventory.sh` plan-file mismatch fixed. Known,
  unremediated exposure: the two real-looking IDs remain in git history (commit `b02b597`) and
  ~16 already-committed evidence JSON files — rotating isn't usually necessary for a sandbox
  subscription, regenerating those files is Phase 6 work.
- **Phase 1 (docs grounded in reality) — done.** README + `docs/01`–`03` written, cross-checked
  against actual code rather than the aspirational plan. Biggest finding: **JML requests are
  validated but not enforced against live cloud access** — no Terraform resource in any of the
  three modules manages per-user group/role membership, so a leaver merge revokes nothing today.
  Also found `security_analyst`/`auditor` collapse to identical RBAC (a labeling issue, not
  under-scoping) and `cloud_engineer`/`devsecops_engineer` collapse to identical RBAC (a real,
  roadmap-worthy gap).
- **Phase 2 (GCP module) — done.** Module was already code-complete; found and fixed a real bug
  (missing `[0]` index on `module.gcp_iam` outputs — `terraform plan` with `enable_gcp=true` had
  never actually been run before and would have hard-failed). Still not deployed against a real
  GCP project (`gcp_project_id` is a placeholder) — a deliberate scope decision, not a gap.
- **Phase 3 (policy-as-code) — done.** `policy/rego/iam.rego` now has an 11+-test Conftest suite
  (`policy/rego/iam_test.rego`) plus a standalone Python test
  (`scripts/test_policy_input_from_plan.py`). Found and fixed two real bugs independent of the
  CI-credential gap below: `run_policy_checks.sh`'s `conftest` invocation was missing
  `--all-namespaces`, so it silently evaluated zero rules and always exited 0 (the policy check
  had been a no-op since it was written); and the break_glass exemption in
  `policy_input_from_plan.py` was a spoofable bare substring match (`"break_glass" in addr`) —
  tightened to anchor on the exact resource construct each module uses, with tests proving both
  the real grants pass and forged addresses are denied. The break_glass-via-joiner/mover Rego
  rules remain dormant (no script produces the `kind: "access_request"` input shape they
  expect) — proven by a test, not just asserted; building that producer is a separate feature.
- **Phase 4 (GitOps governance) — in progress.** `.github/CODEOWNERS` and PR template already
  existed and were mostly correct; added the missing `/policy/` entry to CODEOWNERS. Removed the
  empty `pipelines/github-actions/` (provided no functional value — GitHub Actions only reads
  `.github/workflows/`, and `docs/01` already documents the real CI/CD flow).
- **Not yet implemented**: `docs/04`/`docs/05` are one-line stubs. `environments/dev`/`prod` are
  empty — only `sandbox` is populated. Real AWS permission boundary (still a permissive
  placeholder). Azure credential path in `policy-ci.yml` — the one remaining blocker to "a
  violating PR fails automatically."

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
