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

As of Phase 6 complete (Phases 0–6 of `IAM_Project_Rebuild_Plan.md` all done; Phase 7 — the blog
series — is the user's own writing task, not started):

- **Phase 0 (security hygiene).** Hardcoded Azure subscription/tenant ID defaults removed;
  `.gitignore` covers `terraform.tfvars`, local plan/state artifacts, `__pycache__/`;
  `policy_input_from_plan.py`/`export_policy_inventory.sh` plan-file mismatch fixed. Known,
  unremediated exposure: the two real-looking IDs remain in git history (commit `b02b597`) —
  rotating isn't usually necessary for a sandbox subscription. The evidence files that embedded
  them were scrubbed in Phase 0 (current file contents) and regenerated clean in Phase 6.
- **Phase 1 (docs grounded in reality).** README + `docs/01`–`03` written, cross-checked against
  actual code rather than the aspirational plan. Biggest finding: **JML requests are validated
  but not enforced against live cloud access** — no Terraform resource in any of the three
  modules manages per-user group/role membership, so a leaver merge revokes nothing today. This
  is the single most consequential open gap in the project (see the effort estimate discussion
  below). Also found `security_analyst`/`auditor` collapse to identical RBAC (a labeling issue,
  not under-scoping) and `cloud_engineer`/`devsecops_engineer` collapse to identical RBAC (a
  real, roadmap-worthy gap, not fixed).
- **Phase 2 (GCP module).** Module was already code-complete; found and fixed a real bug
  (missing `[0]` index on `module.gcp_iam` outputs — `terraform plan` with `enable_gcp=true` had
  never actually been run before and would have hard-failed). Still not deployed against a real
  GCP project (`gcp_project_id` is a placeholder) — a deliberate scope decision, not a gap.
  AWS's equivalent output gap (`persona_role_arns` never exposed at root) was closed in Phase 6.
- **Phase 3 (policy-as-code).** `policy/rego/iam.rego` has a 12-test Conftest suite
  (`policy/rego/iam_test.rego`) plus a standalone Python test
  (`scripts/test_policy_input_from_plan.py`). Found and fixed three real bugs, all independent
  of the CI-credential gap: (1) `run_policy_checks.sh`'s `conftest` invocation was missing
  `--all-namespaces`, so it silently evaluated zero rules and always exited 0 — the policy check
  had been a no-op since it was written; (2) fixing that alone immediately false-positived on the
  real, legitimate `break_glass` → `Owner` grant, fixed by computing `allow_owner`/`allow_admin`
  from the resource address; (3) that address check was itself a spoofable bare substring match
  (`"break_glass" in addr`) — tightened to anchor on the exact resource construct each module
  uses, with tests at two levels (Rego + Python) proving both real grants pass and forged
  addresses are denied. The break_glass-via-joiner/mover Rego rules remain dormant (no script
  produces the `kind: "access_request"` input shape they expect) — proven by a test, not just
  asserted; building that producer is still a separate, un-started feature.
- **Phase 4 (GitOps governance).** `.github/CODEOWNERS` and PR template already existed and were
  mostly correct; added the missing `/policy/` entry to CODEOWNERS. Removed the empty
  `pipelines/github-actions/` (no functional value — GitHub Actions only reads
  `.github/workflows/`, and `docs/01` documents the real CI/CD flow).
- **Phase 5 (demo strategy).** Confirmed: Azure live-deployed, AWS/GCP implemented but not
  live-deployed. Correction made while confirming: AWS and GCP don't validate to the same depth
  — GCP's `terraform plan` succeeds cleanly with placeholder credentials, AWS's does not
  (`data.aws_caller_identity.current` needs a live STS call) — only `terraform validate` is
  placeholder-clean for AWS.
- **Phase 6 (evidence & docs closeout).** `docs/04`, `docs/05`, `docs/07` filled in for real.
  `docs/05` leads with an explicit audit-readiness caveat tied to the Phase 1 JML finding —
  evidence proves what Terraform applies, not who has real access. Evidence regenerated with
  scrub-on-generation (never written unscrubbed, even temporarily); `privileged-report-*.json`
  generated for the first time ever. Added an OIDC-based `azure/login` step to `policy-ci.yml` —
  **wired in but not verified to pass in a real CI run**; the Azure AD app registration,
  federated credential, RBAC scoping, and GitHub secrets it depends on are real Azure access this
  rebuild pass deliberately did not provision (see `docs/04` for the exact remaining setup).
- **Deliberately out of scope, documented not fixed**: real per-user group/role membership
  provisioning for Azure/GCP (~8–13 hrs estimated, with real external dependencies — Graph API
  consent, a Cloud Identity/Workspace domain — that could extend it further); AWS's federation
  redesign (bigger still, replaces the account-root trust policy); real AWS permission boundary
  (still a permissive placeholder); `environments/dev`/`prod` (empty); the quarterly
  access-review template (generic, references a `developer` persona that doesn't exist here);
  `export_privileged_report.sh`'s GCP resource-type mismatch (harmless today since GCP isn't
  deployed, would matter once it is).

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
