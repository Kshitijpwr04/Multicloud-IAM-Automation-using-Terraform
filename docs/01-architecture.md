# Architecture

This document walks the full path from "someone needs access" to "an auditor can prove what
access exists and why" — the Identity YAML → Git → CI validation → Terraform → Cloud → Evidence
flow referenced in the README. It describes what's actually implemented, not the aspirational
end state; gaps are called out inline rather than left implicit.

## Diagram

```
 identities/users.yaml, identities/personas.yaml
   (source of truth: who exists, what persona they hold, what a persona means)
        │
        ▼
 identities/access-requests/{joiner,mover,leaver}/*.yaml
   (a proposed change, opened as a pull request)
        │
        ▼
 CI: requests-ci.yml  →  scripts/validate_requests.py
   (fails the PR if: persona is unknown, break_glass requested via joiner/mover,
    joiner email already exists, mover/leaver email doesn't exist, leaver missing
    termination_date)
        │  (on merge)
        ▼
 environments/sandbox/main.tf
   (reads identities/*.yaml directly via yamldecode(), derives active/terminated
    users and desired group memberships per persona as Terraform locals)
        │
        ├─ modules/azure-iam  → Entra ID (msgraph) groups + azurerm_role_assignment
        │                        per persona; break_glass is an explicit, separate
        │                        role assignment, not part of the per-persona loop
        ├─ modules/aws-iam    → one aws_iam_role per persona + managed-policy
        │                        attachments; break_glass gets a short (900s)
        │                        max_session_duration; gated by enable_aws
        └─ modules/gcp-iam    → automation/CI-CD service accounts + persona-based
                                 google_project_iam_member bindings; gated by
                                 enable_gcp
        │
        ▼
 terraform plan  (produces a plan JSON via `terraform show -json`)
        │
        ▼
 scripts/policy_input_from_plan.py
   (extracts azurerm_role_assignment / aws_iam_role_policy_attachment entries
    from the plan JSON into a flat list conftest can evaluate)
        │
        ▼
 CI: policy-ci.yml  →  policy/rego/iam.rego  (conftest test)
   (denies: Azure Owner, AWS AdministratorAccess, break_glass via joiner/mover —
    same rules as validate_requests.py, but enforced against the actual Terraform
    plan rather than just the request YAML)
        │
        ▼
 scripts/inventory/*.sh  →  evidence/
   (tf-outputs-*.json, tfplan-*.json, policy-input-*.json, privileged-report-*.json
    — audit artifacts for access reviews)
```

## Why this shape

- **Persona abstraction, not per-user grants.** A persona (`security_analyst`,
  `cloud_engineer`, `auditor`, `devsecops_engineer`, `break_glass`) maps to a fixed role/policy
  in each cloud. Adding a user never means inventing a new permission set — it means picking
  one of five existing ones. See [`docs/02-personas-rbac-model.md`](02-personas-rbac-model.md).
- **YAML is the source of truth, Terraform reads it.** `identities/users.yaml` and
  `identities/personas.yaml` aren't generated from Terraform state — Terraform's
  `environments/sandbox/main.tf` loads them with `yamldecode(file(...))`. This means the answer
  to "who has access to what" lives in a human-readable file under version control, not buried
  in cloud consoles or Terraform state.
- **Git is the control plane.** Every access change is a PR against
  `identities/access-requests/{joiner,mover,leaver}/`, and it's rejected by CI before a human
  ever has to review it if it's structurally wrong (unknown persona, duplicate joiner, etc.).
- **Break-glass is isolated in Terraform**, not just documented as a rule: Azure's break-glass
  role assignment is a separate resource from the per-persona `for_each` loop
  (`modules/azure-iam/main.tf`), and AWS's break-glass role gets a materially different (short)
  session duration rather than just a different policy.
  In request validation and policy-as-code, the picture is more mixed than it looks at first —
  see [`docs/02-personas-rbac-model.md`](02-personas-rbac-model.md#break-glass-isolation-whats-actually-live-vs-designed-but-dormant)
  for the verified detail: `scripts/validate_requests.py` does currently reject `break_glass`
  joiner/mover requests, but via its generic "unknown persona" check (a side effect of
  `break_glass` being absent from `personas.yaml`), not via the dedicated `if persona ==
  "break_glass"` line, which is unreachable dead code. And `policy/rego/iam.rego`'s two rules
  written specifically to deny `break_glass` via joiner/mover are never actually invoked — no
  script in this repo converts an access-request YAML into the `kind: "access_request"` JSON
  shape those rules expect. The Owner/AdministratorAccess Rego rules *are* live and would
  independently catch a break_glass-shaped over-grant, just not by checking the persona name.
- **Evidence generation is a first-class concern, not an afterthought.** The
  `scripts/inventory/*.sh` scripts exist specifically so that "prove what changed and when" is a
  command to run, not a forensic exercise.

## Component detail

### Identities and requests (`identities/`)
`users.yaml` lists every user with an `email`, `persona`, and `status` (active/terminated).
`personas.yaml` defines what each persona means in plain language — description, privilege
level, intent (see [`docs/02`](02-personas-rbac-model.md) for the full table, including a note
on why `break_glass` isn't in this file at all). Requests live under
`access-requests/{joiner,mover,leaver}/*.yaml` and are validated, not applied directly — merging
a request PR doesn't touch any cloud by itself; it changes `users.yaml`, and the next
`terraform plan`/`apply` against `environments/sandbox` picks up the change. See
[`docs/03-joiner-mover-leaver.md`](03-joiner-mover-leaver.md) for the full request lifecycle.

### Terraform layer (`environments/`, `modules/`)
Only `environments/sandbox` is populated; `dev` and `prod` are empty placeholders. Inside
sandbox, `main.tf` centralizes the persona-to-cloud-role mapping as locals
(`azure_persona_to_role`, `aws_persona_to_policy_arns`, `gcp_persona_to_role`) shared by all
three module calls, and derives `active_users`/`terminated_users`/
`desired_memberships_by_persona` from the YAML for later use (currently exposed as debug
outputs, not yet consumed by anything that reconciles group membership automatically — see
Known gaps below).

AWS and GCP module instantiation is gated by `enable_aws`/`enable_gcp` (both default `false`),
with placeholder credentials (`DUMMY_ACCESS_KEY`, `DUMMY_GCP_TOKEN`, etc.) on aliased "optional"
provider blocks — this is what lets `terraform validate`/`plan` succeed without real AWS/GCP
credentials. Azure has no such gate; it's always instantiated, and needs real credentials
(`az login` device-code auth, or a `terraform.tfvars` with real
`azure_subscription_id`/`azure_tenant_id`) to actually plan against a live tenant.

Because both `aws_iam` and `gcp_iam` use `count = var.enable_x ? 1 : 0`, any root-level output
referencing them must index into them (`module.gcp_iam[0].attr`), not reference them directly.
This was missed for both GCP outputs in `environments/sandbox/outputs.tf` until this rebuild
pass — `terraform plan -target=module.gcp_iam` with `enable_gcp=true` had never actually been
run before, and doing so reproduced a hard failure (`module.gcp_iam is tuple with 1 element —
this value does not have any attributes`). Fixed by adding the `[0]` index; re-verified with a
clean targeted plan (`7 to add, 0 to change, 0 to destroy`). `aws_iam` has the same `count`
pattern but currently has no root output referencing it at all, so there's no equivalent bug
there today — just a smaller gap (its `persona_role_arns` output isn't exposed at the root).

### Policy-as-code (`policy/`, `scripts/policy_input_from_plan.py`)
`policy/rego/iam.rego` holds four `deny` rules (Azure `Owner`, AWS `AdministratorAccess`,
`break_glass` via joiner, `break_glass` via mover), backed by `policy/rego/data.json` (env
config) and `policy/break-glass-allowlist.json` (currently empty — no exceptions have been
approved). `scripts/policy_input_from_plan.py` converts a Terraform plan JSON into the flat
list of `azurerm_role_assignment`/`aws_iam_role_policy_attachment` records the Rego rules
expect; it accepts either a raw plan file (default `tfplan`, rendered via `terraform show
-json`) or an already-rendered `.json` path.

**Known gap:** `policy/opa/` and `policy/conftest/` are both empty (`.gitkeep` only) — there is
no Conftest test suite proving `iam.rego`'s rules actually catch the violations they claim to.
**Known gap:** `.github/workflows/policy-ci.yml` has no Azure authentication step configured
(no `azure/login`, no `ARM_*` credentials), so its `terraform plan` step has no credential path
on a fresh GitHub Actions runner — this predates this rebuild pass and hasn't been verified to
pass end-to-end in CI. Confirmed by actually running `scripts/run_policy_checks.sh` locally: it
fails at Azure authentication once past variable validation.

### Evidence (`scripts/inventory/`, `evidence/`)
Three scripts, three artifact types:
- `export_tf_outputs.sh` → `tf-outputs-*.json` (plain `terraform output -json`).
- `export_policy_inventory.sh` → `tfplan-*.json` + `policy-input-*.json` (plan, then the same
  conversion `run_policy_checks.sh` uses for conftest).
- `export_privileged_report.sh` → `privileged-report-*.json` (scans `terraform show -json`
  state for Azure `Owner`/`Contributor` role assignments and AWS `AdministratorAccess`
  attachments).

**Known gap:** `export_privileged_report.sh` checks for GCP privileged roles under the resource
type `google_project_iam_binding`, but `modules/gcp-iam` actually creates
`google_project_iam_member` resources — so the privileged-access report currently can never
match a GCP entry, silently. Not fixed as part of this docs pass; flagged here so it doesn't
get rediscovered from scratch later.

## Known gaps (see README roadmap for the full list)
- No Conftest test suite for `policy/rego/iam.rego`.
- `policy/rego/iam.rego`'s two break_glass-via-joiner/mover rules are never invoked in practice
  — no script produces the `kind: "access_request"` input shape they expect (see
  [`docs/02`](02-personas-rbac-model.md#break-glass-isolation-whats-actually-live-vs-designed-but-dormant)).
- No Azure credential path in `policy-ci.yml`.
- `export_privileged_report.sh`'s GCP resource-type mismatch (above).
- AWS permission boundary is a placeholder (`Allow: *` on `*`), not real least-privilege.
- GCP module is not deployed against a real project (`gcp_project_id` is still a placeholder).
  Its `terraform plan` path with `enable_gcp=true` is now verified clean as of this pass (see
  above) — previously it would have actively failed, not just been untested.
- `desired_memberships_by_persona` (in `environments/sandbox/main.tf`) is computed but not yet
  consumed by anything that reconciles actual group membership against it — it's exposed as a
  debug output today, not an enforcement mechanism.
