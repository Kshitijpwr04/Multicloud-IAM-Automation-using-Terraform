# Session Log — IAM Project Rebuild (Phases 0–6)

A complete record of one Claude Code session working through
`IAM_Project_Rebuild_Plan.md` phase by phase, from initial kickoff through final
pre-push verification. Written for future reference (including as raw material
for the Phase 7 blog series) — every bug, every decision, and why, in order.

---

## Kickoff

Instruction: read `CLAUDE.md` and `IAM_Project_Rebuild_Plan.md` fully, work through
the plan phase by phase, don't skip Phase 0, state intent before changes, run real
validation after changes, flag rather than silently resolve conflicts with the plan.

**First discovery, before any changes were made**: auditing the actual working tree
against CLAUDE.md's "Current status" section showed the status section was
substantially stale. The repo had a large amount of legitimate, uncommitted work
already sitting in the working tree:
- `modules/gcp-iam` was **not** empty (contradicting CLAUDE.md) — fully built
  (`variables.tf`, `main.tf` with service accounts + persona IAM bindings,
  `outputs.tf`).
- `policy/rego/iam.rego` already had real guardrail rules (deny Azure `Owner`, deny
  AWS `AdministratorAccess`, deny `break_glass` via joiner/mover).
- `.github/CODEOWNERS`, a PR template, and two CI workflows
  (`requests-ci.yml`, `policy-ci.yml`) already existed.
- AWS break-glass session-duration hardening existed (900s vs. 3600s standard).
- Even `CLAUDE.md` and `IAM_Project_Rebuild_Plan.md` themselves were untracked.

**Decision**: commit this pre-existing work as a clean baseline first (7 commits,
grouped logically), then execute the actual new Phase 0 hygiene work on top, so
git history reflects reality before building further. Confirmed with the user
before proceeding, since this was a significant scope discovery mid-plan.

---

## Phase 0 — Security & hygiene

**Baseline recovery (Step A, 7 commits)**: project docs, GCP module completion, AWS/Azure
hardening, sandbox provider toggles + persona-engine locals, joiner-side break_glass
guardrail, policy-as-code scaffolding, GitOps governance files.

**Phase 0 fixes (Step B, 4 commits)**:
1. Removed hardcoded real-looking Azure `subscription_id`/`tenant_id` defaults from
   `environments/sandbox/variables.tf` — made required vars with no default.
2. Broadened `.gitignore`: `terraform.tfvars`, `*.auto.tfvars`, `tfplan`, `tfplan-*`,
   `tfstate.json`, `policy-input.json`, `local.desired_memberships_by_persona`.
   Deleted the stray untracked copies already littering `environments/sandbox/`.
3. **Bug found and fixed**: `scripts/inventory/export_policy_inventory.sh` called
   `scripts/policy_input_from_plan.py` with no argument. That script hardcoded
   reading a plan file literally named `tfplan`, while the shell script generates a
   *timestamped* plan (`tfplan-${TS}`) — so it was silently reading stale leftover
   plan data instead of the plan it just generated. Fixed by having the Python
   script accept an explicit path argument.
4. Corrected `CLAUDE.md`'s stale "Current status" section to match reality.

**Follow-up investigation** (user-directed):
- Confirmed via `git log`/`git blame` that neither `identities/users.yaml` nor
  `identities/access-requests/mover/MR-0001-example.yaml` were touched by any of
  this session's commits — the email mismatch between them predated the session
  (introduced 2026-02-19 in commit `7382a23`, a month after `users.yaml` was last
  edited 2026-01-22 in `2f47dd0`).
- Confirmed the GitHub repo is **public**.
- Found the real subscription/tenant IDs were present in **16** already-committed
  evidence JSON files (not the ~18 originally estimated), introduced in two commits
  (`c690d48`, `cf23c8d`).
- **Fixed**: `MR-0001-example.yaml`'s email, from a real personal Gmail address to
  the `kp@example.com` placeholder already used elsewhere in `users.yaml` (commit
  `7732c1f`).
- **Fixed**: scrubbed all 16 evidence files. Sample diff shown for approval before
  running at scale. Expanded scope (user-approved) to also scrub 12 additional
  real, tenant-specific `principal_id`/role-assignment-id values found during the
  audit — while explicitly leaving alone 4 GUIDs confirmed to be **global, non-secret
  Azure constants** (3 built-in role-definition IDs for Owner/Reader/Contributor,
  and the well-known public Azure CLI client ID). Verified with a repo-wide grep
  showing zero real IDs remaining (commit `19fc185`).

---

## Phase 1 — Ground the docs in reality

**Pre-writing inventory** surfaced that `identities/personas.yaml` does not include
`break_glass` as a registered persona at all, despite it being fully wired through
every Terraform module and referenced by `validate_requests.py`'s guardrail checks.

**README.md written** (commit `ad2f76a`), but not before a user-directed fact-check
surfaced two real problems:
- `scripts/run_policy_checks.sh`, when actually run, failed — not just due to the
  Phase 0 variable-default removal (a real regression, not yet fixed at this
  point), but also due to a **deeper, pre-existing gap**: `policy-ci.yml` has no
  Azure authentication step configured at all (no `azure/login`, no `ARM_*`
  secrets), so the check could never have completed on a fresh CI runner regardless
  of anything this session touched.
- A usage bug in the README's own instructions: `run_policy_checks.sh` must be
  invoked from inside `environments/sandbox` (it doesn't `cd` there itself) — found
  by actually running the documented command and watching it fail differently than
  expected.
- **Decision** (user-directed): don't fix the CI regression yet, just document it
  accurately; keep the README's existing wording but add a footnote caveat.

**`docs/01-architecture.md` written** (commit `b2fdbcb`) — full component walkthrough
with every known gap called out inline, including a bug found while documenting the
evidence scripts: `export_privileged_report.sh` checks for GCP privileged roles
under the resource type `google_project_iam_binding`, but `modules/gcp-iam` actually
creates `google_project_iam_member` — so it can never match a GCP entry (not fixed,
flagged).

**`identities/personas.yaml` typos fixed** (commit `3262a10`) — "Resposible" →
"Responsible", "proejct" → "project", and a run-on phrase cleaned up. No semantic
change.

**`docs/02-personas-rbac-model.md` written** (commit `f41c8bf`) — persona table
cross-checked against the actual Terraform locals, not just the YAML. Three
distinct findings, deliberately not conflated:
1. `security_analyst`/`auditor` collapse to identical (read-only) RBAC — assessed
   as a **labeling/documentation issue**, not under-scoping: the read-only mapping
   is actually the *correct*, least-privilege-consistent choice; the real problem
   is `personas.yaml`'s undefined `privilege_level` semantics.
2. `cloud_engineer`/`devsecops_engineer` collapse to identical RBAC — assessed as a
   **real, roadmap-worthy scope gap**: two personas with genuinely different
   declared responsibilities have no actual permission distinction today.
3. `break_glass`'s absence from `personas.yaml` produces **verified unreachable
   dead code** in `validate_requests.py`'s joiner path (traced the exact control
   flow: the generic "unknown persona" check fails the request before the
   dedicated `break_glass` check is ever reached).

  User pushback led to a **correction mid-draft**: the initial framing called
  `break_glass`'s absence from `personas.yaml` "arguably a feature" of the
  isolation design. Re-examined and reversed that claim — the evidence (Terraform
  locals treat `break_glass` as first-class everywhere else; the dead code's own
  comment suggests the author expected it to be reachable) points to an
  **oversight**, not a deliberate defense-in-depth layer.

  A second correction followed from testing rather than reasoning: verifying
  whether the Rego break_glass rules provided independent protection revealed they
  have **no input producer at all** in this repo's pipeline — nothing converts an
  access-request YAML into the `kind: "access_request"` shape those rules require.
  This meant the original docs/01 claim ("a second, structurally different check")
  was wrong and needed correcting there too (commit `7a33a6d`).

**`docs/03-joiner-mover-leaver.md` written** (commit `eb60189`) — the single biggest
finding of the whole session: **merging a joiner/mover/leaver request does not, by
itself, grant or revoke any real cloud access.** Verified by tracing every module:
Azure creates groups and assigns roles *to the groups* but has no
add/remove-member resource; GCP binds IAM roles to a Google Group *by email* but
manages no group membership; AWS's roles are assumable by any principal in the
account (trust policy trusts the account root, not individuals) — none of the
three modules manage per-user membership at all. `desired_memberships_by_persona`
is computed in Terraform locals but only exposed as a debug output, never
reconciled into anything real.

`README.md` updated (commit `d0b6f04`) to state this plainly, near the top of the
roadmap, and to correct the Azure "live and tested" demo claim to be precise about
*what* was tested (scaffolding only — verified against real plan evidence: exactly
one resource group, six role assignments, five Entra ID groups were ever actually
applied; no user was ever added to a group).

`docs/04`/`docs/05` added as one-line stubs (commit `9e12fec`), per plan.

One incidental change (a `.terraform.lock.hcl` provider version bump from local
testing) was found and **reverted**, not committed — not part of the requested work.

---

## Phase 2 — Finish the GCP module

Before doing any work, produced an **effort estimate** for the Phase 1 JML gap
(per-user membership provisioning), at the user's request, to inform prioritization:
roughly 4–7 hrs for Azure (Graph API consent risk), 4–6+ hrs for GCP (needs a real
Cloud Identity/Workspace domain, a bigger external dependency than Azure's), ~8–13
hrs combined — with AWS's fix (replacing the account-root trust policy with real
federation) assessed as a separate, larger redesign not estimated in detail.
**Decision** (user): defer this work, document it as a deliberate scope boundary,
prioritize Phases 2–4 instead as lower-risk, boundable work.

**Bug found and fixed**: re-scoping Phase 2 meant actually testing the GCP module
rather than re-asserting "code-complete." Running
`terraform plan -target=module.gcp_iam` with `enable_gcp=true` for the first time
ever reproduced a real failure: two root outputs in
`environments/sandbox/outputs.tf` referenced `module.gcp_iam.<attr>` without the
`[0]` index required by its `count`-based instantiation. Fixed and reverified
(`Plan: 7 to add, 0 to change, 0 to destroy`, no errors) — commit `03933e1`.

Corrected README/docs/01 wording from "never `plan`/`apply`-tested" to be precise
that it would have actively *failed*, not just gone untested (commit `cf9b658`).

---

## Phase 3 — Policy-as-Code

**Pre-writing inventory** (requested before any test code) surfaced something far
more serious than the already-documented dormant-rule/CI-credential gaps:

**Bug found and fixed**: `scripts/run_policy_checks.sh`'s `conftest test`
invocation never specified `--all-namespaces`. Conftest defaults to namespace
`main`; `iam.rego` declares `package iam.guardrails`. Without the flag, conftest
silently evaluates **zero rules and exits 0 regardless of input** — reproduced the
exact invocation against real data containing an actual `Owner` grant and got
`0 tests, 0 passed... exit code: 0`. **The entire policy check had been a no-op
since it was written**, for a reason completely independent of the already-known
CI-credential gap. Fixed by adding the flag (commit `159607f`).

**Bug found and fixed**: fixing the namespace bug alone immediately caused a false
positive on the real, legitimate, already-deployed `break_glass` → `Owner` role
assignment, because `policy_input_from_plan.py` hardcoded
`meta.allow_owner`/`allow_admin` to `false` for every entry with no exception
mechanism. Fixed by computing those flags from whether the Terraform resource
address corresponds to the break_glass persona (commit `544bf3d`). User confirmed
fixing both bugs together, rather than fixing one and leaving the other as a
known false-positive.

**11-test Conftest suite written** (`policy/rego/iam_test.rego`, commit `5299740`),
colocated with the policy rather than under the empty `policy/opa/`/
`policy/conftest/` stub directories (a deliberate layout choice, since conftest
needs to load tests from the same `-p` path as the policy). Per user direction,
the dormant break_glass-via-JML rules were made **provably dormant** via a test
that feeds them a real captured sample of the pipeline's actual output and shows
none of it has a `kind` field — rather than building the missing input-producer
script (a separate feature, out of scope for a test-writing pass). Verified the
suite catches real regressions: deliberately typo'd the Owner-role comparison in
`iam.rego`, confirmed the relevant test failed (10/11 passed), reverted, confirmed
11/11 passed again.

Docs updated across README/docs/01/docs/03 to reflect both bugs and stop
overstating the Owner/AdministratorAccess rules as simply "live" (commit
`34d2666`).

**Follow-up, user-directed security review of the break_glass exemption**:
"How tight is the address match — could a non-break-glass resource be crafted to
slip through?" Answer: **yes, exploitable.** The exemption logic
(`is_break_glass = "break_glass" in addr`) was a bare substring match. Demonstrated
with three concrete forged addresses (a relabeled Azure resource, a renamed
module, a differently-labeled AWS resource reusing the `break_glass::` key
prefix) — all three slipped past the check, since `environments/**`/`modules/**`
are exactly the paths a PR could touch to craft this.

**Fixed** (commit `49dfc3d`): tightened the match to anchor on the *specific*
resource construct each module actually uses for break_glass — Azure must be the
single, non-`for_each` `break_glass_owner` resource; AWS must be specifically the
`persona` resource's `for_each` entry keyed by a `break_glass::` prefix (checking
both the resource label and the key prefix, closing a second-order forgery the
first fix alone would have missed). Extracted as a standalone, testable
`is_break_glass(rtype, addr)` function.

Added a **direct Python test** for the matching function itself (commit
`2300830`) — recognizing that the Conftest/Rego test alone only proves the Rego
layer trusts whatever `meta.allow_owner` value it's handed, not that the address
logic resists spoofing. Verified this test also catches a regression (reverted to
the old loose logic, confirmed exactly the 3 forged cases failed, reverted back).

Added the requested Conftest test for the forged-address case too (commit
`4c8dae4`), with an explicit note in the test itself about what it does and
doesn't prove, so the two test layers aren't confused for each other.

---

## Phase 4 — GitOps governance files

Audit found: `.github/CODEOWNERS` already correctly required review on
`identities/` and `modules/` — **`policy/` was missing entirely** despite Phase 3
adding real security-relevant guardrail logic there. PR template already existed
and was functionally correct (different directory-based convention than the plan
named, but equivalent). CI workflows already correct (audited in Phase 3).
`pipelines/github-actions/` was genuinely empty and provided no functional value
(GitHub Actions only reads `.github/workflows/`; `docs/01` already documents the
real CI/CD flow) — **removed**, rather than populated with a redundant doc.

Fixed: added `/policy/` to CODEOWNERS, removed the empty folder (commit
`d699488`). `CLAUDE.md`/plan doc brought current through Phase 4 (commit
`d2309f8`).

---

## Phase 5 — Confirm the demo strategy

Confirming the already-adopted strategy (Azure live-deployed; AWS/GCP implemented
but not live-deployed) surfaced one more real inaccuracy while double-checking
Phase 2/3 findings against it:

**Bug found (documentation, not code)**: README/docs/01 claimed AWS and GCP were
equally "validated via `terraform validate`/`plan` with placeholder credentials."
True for GCP (verified clean in Phase 2). **Not true for AWS** — running
`terraform plan -target=module.aws_iam` with `enable_aws=true` genuinely fails
(`Error: reading STS Caller Identity ... InvalidClientTokenId`, exit code 1),
because `data.aws_caller_identity.current` makes a live STS call that isn't
covered by the provider's `skip_credentials_validation`/`skip_requesting_account_id`
flags (those only suppress the *provider's own* implicit lookup, not this
explicit `data` block). Only `terraform validate` is placeholder-clean for AWS.

**Decision** (user): correct the wording, don't attempt to redesign the module to
avoid the live STS dependency — needing real credentials for a real trust-policy
ARN is reasonable behavior. Fixed (commit `3c5757d`), Phase 5 checked off (commit
`f26d7d7`).

---

## Phase 6 — Evidence & docs closeout

**Evidence regeneration**, with an explicit scrub-on-generation requirement (never
write real IDs even temporarily). Constraint discovered up front: a fresh live
`terraform plan` against Azure is not obtainable in this session — the
devcontainer's cached `az login` session has expired
(`AADSTS700082: refresh token has expired due to inactivity`), and non-interactive
re-auth isn't possible.

What was actually regenerated, and how:
- `tf-outputs-*.json` and `privileged-report-*.json` — real, fresh, generated
  directly from local Terraform state (`terraform output -json` /
  `terraform show -json`, neither needs live credentials). The privileged report
  had **never been generated before this session** — no prior file existed.
- `policy-input-*.json` — regenerated using the now-fixed converter, but against
  the most recent *existing* plan snapshot rather than a brand-new live plan,
  clearly labeled as such rather than implied to be fresh. Demonstrates the Phase
  3 fix concretely: the real break_glass grant is now correctly exempted
  (`allow_owner: true`) instead of the old buggy always-`false` output.

All three scrubbed in memory before ever touching the repo, using the same
mapping established in Phase 0 (confirmed identical GUIDs in current state — same
unchanged deployment). Verified clean with a repo-wide grep. Committed (`4878483`).

**`docs/04-guardrails-policy-as-code.md` written** — covers the 4 rules, both
Phase 3 bugs, the break_glass exemption and its two-layer test coverage, the
dormant JML rules, and an honest statement that CI enforcement is not fully
achieved yet.

**`docs/05-access-reviews-audit-evidence.md` written** — leads deliberately with
the audit-readiness caveat requested: evidence proves what Terraform *applies*,
not who has real access, directly tied to the Phase 1 JML finding (a leaver merge
produces no corresponding change anywhere in `evidence/`, because there's nothing
in Terraform to show). Also flags (not fixed): `evidence/demo/` and
`evidence/reviews/` contain an identical, undeduplicated quarterly review
template, and that template is generic — its example row uses a `developer`
persona that doesn't exist in this project's actual 5-persona model.

**`docs/07-demo-runbook.md` written**, twice. First draft covered similar ground
in 8 steps (committed as `0ae99e6`); rewritten in full per specific user-requested
structure (7 steps in a specific order: validator → `terraform validate` → Azure
live plan/apply → GCP targeted plan → AWS validate-only → policy checks/tests →
evidence generation), with every credential-free command re-verified live while
writing it, and every known limitation cited by commit hash.

**Two additional gaps closed** at user request, beyond the plan's original Phase 6
scope:
1. `modules/aws-iam`'s `persona_role_arns` output (computed but never exposed at
   root, a Phase 2-era gap) — exposed in `environments/sandbox/outputs.tf`,
   verified with `terraform validate` and both `enable_aws` states (commit
   `17266bb`).
2. An Azure credential path added to `.github/workflows/policy-ci.yml` — OIDC/
   federated `azure/login@v2` (no long-lived secret), explicitly **not**
   provisioning any actual Azure credentials (that's real Azure access, left to
   the repo owner). Provided the exact Azure-side setup needed: an app
   registration, a federated credential scoped to the `pull_request` trigger
   scenario specifically (not the branch-push scenario), a `Reader` RBAC role
   scoped to the `rg-iam-sandbox` resource group only (not subscription-wide, not
   the same broad access as an interactive login), Microsoft Graph API
   permissions for the `msgraph` provider's separate auth needs, and three GitHub
   secrets. Framed honestly throughout as "wired in, not verified to pass in a
   real CI run" (commits `8a2e296`, `c2ed540`).

Final status rewrite across `CLAUDE.md` and `IAM_Project_Rebuild_Plan.md` (commit
`681df45`), including a "deliberately out of scope, documented not fixed" section
(per-user provisioning, AWS's federation redesign, the AWS permission-boundary
placeholder, the empty `dev`/`prod` environments, the stale review template, the
GCP resource-type mismatch in the privileged report script).

**Process note**: a full summary was given claiming 41 total commits — this
turned out to be wrong by one. `docs/05`'s complete draft had been shown for
review earlier but never actually committed (its content only went from a
one-line stub straight to being edited further, with no intermediate "write it
for real" commit ever made). Caught by checking `git log -- docs/05...` directly
rather than trusting the earlier claim, and committed immediately (`aa976b9`).

---

## Final pre-push verification

Requested explicitly as a distinct, non-skippable checkpoint before this became
public and permanent:

1. `git status` — working tree already fully clean, nothing to commit (the AWS
   output fix and `policy-ci.yml` OIDC changes were already committed in the prior
   turn).
2. **Full safety scan of the entire tracked tree** (not just `evidence/`): searched
   for the two known real Azure IDs, the 12 known real per-object GUIDs, *every*
   GUID-shaped string in the repo (to catch anything not already accounted for),
   every email address outside `@example.com`-style placeholders, and AWS
   access-key-shaped strings.

   **Found a real leak**: `docs/07-demo-runbook.md` quoted a real historical
   validator failure message *verbatim* as an illustrative example — which
   contained the same real personal email already scrubbed out of
   `MR-0001-example.yaml`'s actual data back in Phase 1, reintroduced into a new
   file despite being fixed at the source. Fixed by generating a fresh, synthetic
   failure example instead (temporarily pointing the same file at a
   `nonexistent.user@example.com` address, capturing the real output, reverting
   immediately) — commit `aaa3e35`. Re-ran the full scan after the fix: clean.
3. Full `git log --oneline` shown — 62 commits total in repo history, 42 from this
   session.
4. **Push attempt blocked**, not by git, but by Claude Code's own auto-mode
   permission classifier: pushing directly to `main` (the default branch) was
   flagged as bypassing PR review, which it judged a generic "push to origin"
   instruction hadn't explicitly authorized. Did not attempt to route around this
   via another tool — reported it plainly and asked the user to either push it
   themselves or explicitly confirm they want a direct push to `main`.

---

## Consolidated bug list (all found and fixed unless noted)

1. `export_policy_inventory.sh`/`policy_input_from_plan.py` plan-filename mismatch
   (Phase 0).
2. Real Azure subscription/tenant IDs hardcoded as variable defaults (Phase 0).
3. Real IDs embedded in 16 committed evidence files, plus 12 additional
   tenant-specific object IDs beyond the two originally scoped (Phase 0).
4. Stale personal email in `MR-0001-example.yaml`, breaking the validator (Phase 0
   follow-up).
5. `security_analyst`/`auditor` privilege-level labeling inconsistent with actual
   RBAC (Phase 1, **documented, not fixed** — correctly assessed as not a real gap).
6. `cloud_engineer`/`devsecops_engineer` RBAC collapse (Phase 1, **documented, not
   fixed** — real roadmap item).
7. `break_glass` missing from `personas.yaml`, causing dead code in
   `validate_requests.py` (Phase 1, **documented, not fixed** — likely oversight).
8. JML requests don't enforce real access changes — no per-user membership
   management in any cloud module (Phase 1, **documented as the top roadmap
   item, not fixed** — a deliberate, estimated scope boundary).
9. `export_privileged_report.sh`'s GCP resource-type mismatch
   (`google_project_iam_binding` vs. `google_project_iam_member`) (Phase 1,
   **documented, not fixed**).
10. GCP module's missing `[0]` index on root outputs, would have hard-failed on
    first real use (Phase 2, fixed).
11. Policy check's missing `--all-namespaces` flag — silently evaluated zero
    rules, always exited 0 (Phase 3, fixed).
12. break_glass exemption false-positived on the real legitimate grant (Phase 3,
    fixed, alongside #11).
13. break_glass exemption was a spoofable bare substring match, exploitable via
    resource/module naming (Phase 3, fixed, with tests at two independent levels).
14. `.github/CODEOWNERS` missing a `/policy/` entry (Phase 4, fixed).
15. AWS's `terraform plan` doesn't actually succeed with placeholder credentials
    (unlike GCP's), contradicting prior documentation (Phase 5, wording fixed;
    module behavior intentionally left as-is).
16. `aws_iam`'s `persona_role_arns` output never exposed at root (Phase 2-era gap,
    fixed in Phase 6).
17. `docs/07`'s illustrative failure example leaked a real personal email
    (found and fixed during final pre-push safety scan).

## Deliberate, documented scope boundaries (found, intentionally not fixed)

- Per-user group/role membership provisioning for Azure and GCP (~8–13 hrs
  estimated, real external dependencies).
- AWS's account-root trust policy (needs a bigger federation redesign).
- AWS's permission boundary (still a permissive placeholder).
- `environments/dev`/`environments/prod` (empty).
- The dormant break_glass-via-joiner/mover Rego rules (no input-producer script
  built).
- The quarterly access-review template (generic, references a nonexistent
  persona; duplicated across two directories).
- `export_privileged_report.sh`'s GCP resource-type mismatch.
- The Azure credential path in `policy-ci.yml` is wired in but genuinely
  unverified — depends on Azure-side setup only the repo owner can do.

## Final state at end of session

62 total commits in repo history (42 from this session). Working tree fully
clean, all five final safety checks passed. Local `main` is 42 commits ahead of
`origin/main` — **not yet pushed**, pending the user's explicit choice between
pushing it themselves or re-confirming a direct push to `main` is intended.
