# Access reviews / audit evidence

**Read this section before the rest: what `evidence/` proves, and what it doesn't.**

Everything under `evidence/` is generated from Terraform plan/state — it proves what Terraform
*has applied or would apply*. It does **not** prove what access actually exists for a given
user, and it does not prove that a joiner/mover/leaver request had any real effect. Per the
Phase 1 finding (full detail in
[`docs/03-joiner-mover-leaver.md`](03-joiner-mover-leaver.md#the-most-important-thing-to-understand-first)):
no Terraform resource in any of the three cloud modules manages per-user group/role membership.
Azure creates persona groups and assigns roles *to the groups*; nothing adds or removes
individual users as members. So a leaver request merging, or a user's `status` changing to
terminated in `identities/users.yaml`, produces **no corresponding change anywhere in
`evidence/`** — there's nothing in Terraform's plan/state for it to show, because there's
nothing in Terraform that acts on it. An access review built solely from this evidence would
correctly show which roles are assigned to which *groups*, and would show nothing at all about
which *people* currently hold those roles. Don't present this evidence as proof of who has
access today — it's proof of what the infrastructure grants to which group/role, which is a
narrower and different claim.

## What `evidence/` actually contains

- **`evidence/inventory/`** — the fuller, accumulating historical log: `tf-outputs-*.json`,
  `tfplan-*.json`, `policy-input-*.json`, and (as of this Phase 6 pass) `privileged-report-*.json`.
- **`evidence/demo/`** — a curated subset (one of each artifact type) plus a `README.md`
  explaining it's a portfolio-review sample, and a copy of the quarterly review template.
- **`evidence/reviews/`** — a second, identical copy of the quarterly review template (see Known
  gaps below — this duplication wasn't fixed as part of this pass).
- **`evidence/exports/`**, **`evidence/scripts/`** — both empty (`.gitkeep` only).

## How it's generated (`scripts/inventory/`)

- **`export_tf_outputs.sh`** → `tf-outputs-*.json`. Plain `terraform output -json` against local
  state. No live cloud credentials needed — confirmed by running it directly in this pass.
- **`export_policy_inventory.sh`** → `tfplan-*.json` + `policy-input-*.json`. Requires a real
  `terraform plan`, which for the Azure module requires live, authenticated Azure access
  (`az login` or `terraform.tfvars` with real credentials) — this is the one export that can't
  run without real cloud access.
- **`export_privileged_report.sh`** → `privileged-report-*.json`. Scans `terraform show -json`
  (local state, no plan needed — also no live credentials required) for Azure `Owner`/
  `Contributor` role assignments and AWS `AdministratorAccess` attachments. **Known gap,
  documented in [`docs/01`](01-architecture.md), not fixed here**: it checks for GCP privileged
  roles under `google_project_iam_binding`, but `modules/gcp-iam` actually creates
  `google_project_iam_member` — so it can never match a GCP entry. This didn't affect the
  Phase 6 regeneration since GCP isn't deployed anyway (no GCP entries exist in state to miss
  either way), but the bug is real and would matter the moment GCP goes live.

## Regenerated in this pass (Phase 6)

`tf-outputs-20260703-002010.json` and `privileged-report-20260703-002010.json` are real,
generated directly from the actual local Terraform state (no live credentials needed for
either). `policy-input-20260703-002010.json` demonstrates the Phase 3 fix concretely — the real
`break_glass` → `Owner` grant is now correctly exempted (`allow_owner: true`) instead of the old
buggy always-`false` output — but it's derived from the most recent *existing* plan snapshot,
not a brand-new live `terraform plan`: a fresh plan against Azure isn't obtainable in this
session (the cached `az login` session has expired, confirmed via
`AADSTS700082: refresh token has expired due to inactivity`, and non-interactive re-auth isn't
possible here). All three were scrubbed of the real subscription/tenant IDs *before* being
written anywhere in the repo, not scrubbed after the fact — verified with a repo-wide grep
across all of `evidence/` showing zero remaining real IDs.

## Known gaps

- **The central one, restated**: this evidence pipeline has no way to show actual per-user
  access — only role-to-group/role-to-persona assignments. Closing this requires the same
  membership-reconciliation work flagged in `docs/03`, not a change to the evidence scripts.
- `export_privileged_report.sh`'s GCP resource-type mismatch (above).
- `evidence/demo/` and `evidence/reviews/` both contain an identical
  `quarterly-access-review-template.md`. Not deduplicated in this pass.
- The quarterly review template itself is generic, not tailored to this project's actual
  persona model — its example row uses a persona called `developer`, which doesn't exist in
  `identities/personas.yaml` (the real personas are `security_analyst`, `cloud_engineer`,
  `auditor`, `devsecops_engineer`, `break_glass`). Left as-is; flagged here rather than silently
  filled in with fabricated-looking "real" data.
