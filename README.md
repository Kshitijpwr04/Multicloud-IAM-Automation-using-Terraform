# Multi-Cloud IAM Automation using Terraform

A GitOps-driven, persona-based IAM governance platform across Azure, AWS, and GCP.
Access is requested through pull requests, validated in CI, and applied through Terraform —
never granted by hand.

## Problem statement

Most IAM sprawl comes from ad-hoc access: someone gets a role assigned directly, in a console,
because it was the fastest way to unblock them. Nobody remembers why, nobody reviews it later,
and "least privilege" quietly erodes cloud by cloud. This project is an attempt to make access
changes look like code changes — reviewable, auditable, and consistent across three different
IAM systems that don't otherwise share a model.

Concretely, it does three things:
1. **Models access as personas, not per-user grants.** A fixed, small set of personas maps to
   concrete roles/policies in each cloud, so "what can a `cloud_engineer` do" has one answer
   instead of three (or three hundred).
2. **Turns access changes into a joiner/mover/leaver Git workflow.** A new hire, a role change,
   or an offboarding is a YAML file in a pull request, validated by a script before it can merge.
3. **Treats policy as code.** Guardrails (e.g. "break-glass access can never be granted through
   a normal request") are meant to be enforced by an automated check against the Terraform plan,
   not just by convention.

## Architecture

```
 identities/*.yaml  (source of truth: who exists, who has which persona)
        │
        ▼
 identities/access-requests/{joiner,mover,leaver}/*.yaml   (proposed changes, via PR)
        │
        ▼
 scripts/validate_requests.py   (CI: requests-ci.yml)
        │  rejects: unknown personas, break_glass via joiner/mover,
        │           duplicate joiners, missing leaver fields
        ▼
 environments/{sandbox,dev,prod}/  (Terraform, reads identities/*.yaml directly)
        │
        ├── modules/azure-iam   → Entra ID groups + RBAC role assignments
        ├── modules/aws-iam     → IAM roles + managed-policy attachments
        └── modules/gcp-iam     → service accounts + project IAM bindings
        │
        ▼
 terraform plan
        │
        ▼
 scripts/policy_input_from_plan.py → policy-input.json
        │
        ▼
 policy/rego/iam.rego + conftest   (CI: policy-ci.yml)
        │  denies: Azure Owner, AWS AdministratorAccess, break_glass via joiner/mover
        ▼
 scripts/inventory/*.sh  → evidence/  (exported plan/output/privileged-access JSON,
                                        for audit trails and access reviews)
```

See [`docs/01-architecture.md`](docs/01-architecture.md) for the full walkthrough,
[`docs/02-personas-rbac-model.md`](docs/02-personas-rbac-model.md) for the persona table, and
[`docs/03-joiner-mover-leaver.md`](docs/03-joiner-mover-leaver.md) for the request flow.

## What's implemented vs. roadmap

This section is deliberately honest about the gap between "designed" and "built." A README that
oversells its own project is worse than one with a visible roadmap.

### Implemented and working
- **Azure module** (`modules/azure-iam`): Entra ID (Microsoft Graph) groups per persona, RBAC
  role assignments, break-glass kept as an explicit, isolated role assignment rather than part
  of the general per-persona loop.
- **AWS module** (`modules/aws-iam`): one IAM role per persona, managed-policy attachments,
  break-glass gets a short 900-second max session duration. The permission boundary is still a
  placeholder policy (`Allow: *` on `*`) — real least-privilege boundaries are not implemented.
  `terraform validate` passes with the placeholder credentials, but `terraform plan` does not:
  `data.aws_caller_identity.current` makes a live STS API call to build the trust-policy ARN,
  which the `DUMMY_ACCESS_KEY`/`DUMMY_SECRET_KEY` placeholders can't satisfy (confirmed —
  `terraform plan -target=module.aws_iam` with `enable_aws=true` fails with
  `InvalidClientTokenId`, exit code 1). Unlike GCP, this isn't just untested; `plan` genuinely
  requires real AWS credentials. Not treated as a bug to fix — needing valid STS access to build
  a real trust-policy ARN is reasonable behavior, just worth stating precisely rather than
  lumping AWS in with GCP's placeholder-clean-plan story.
- **GCP module** (`modules/gcp-iam`): automation + CI/CD service accounts, persona-based project
  IAM bindings via Google Groups. Gated off by default (`enable_gcp = false`), and
  `gcp_project_id` still defaults to a placeholder, so it's not deployed against a real GCP
  project. It's more than "untested," though: `terraform plan -target=module.gcp_iam` with
  `enable_gcp=true` had never actually been run before this rebuild pass, and doing so for the
  first time reproduced a real failure — two root outputs referenced `module.gcp_iam.<attr>`
  without the `[0]` index required by its `count`-based instantiation, so enabling it would have
  hard-failed on first use. Fixed and verified (`Plan: 7 to add, 0 to change, 0 to destroy`, no
  errors) as part of this pass; the module itself needed no changes.
- **Identity source of truth**: `identities/users.yaml`, `identities/personas.yaml`.
- **Request validation**: `scripts/validate_requests.py` — enforces persona validity, blocks
  `break_glass` via joiner/mover, checks joiner/leaver preconditions. Wired into CI
  (`requests-ci.yml`).
- **Evidence export**: `scripts/inventory/*.sh` generate Terraform output/plan/privileged-access
  JSON into `evidence/`.
- **Policy-as-code**: `policy/rego/iam.rego` implements the same guardrails as the Python
  validator, evaluated against the Terraform plan JSON, with an 11-test suite
  (`policy/rego/iam_test.rego`) proving the rules catch real violations — including a test that
  proves the two break_glass-via-joiner/mover rules are *dormant* (no script produces the input
  shape they expect), rather than just claiming it. Two real bugs were found and fixed getting
  here, independent of the CI credential caveat below: `run_policy_checks.sh`'s `conftest`
  invocation was missing `--all-namespaces`, so it silently evaluated zero rules and always
  exited 0 — the policy check had been a no-op since it was written; and fixing that alone
  immediately false-positived on the real, legitimate `break_glass` → `Owner` grant, now fixed by
  computing `allow_owner`/`allow_admin` from the resource address in
  `policy_input_from_plan.py`. Full detail in [`docs/01`](docs/01-architecture.md).
  *(Caveat: `policy-ci.yml` now has an OIDC-based `azure/login` step (client-id/tenant-id/
  subscription-id from GitHub secrets, no long-lived client secret) wired in, but this has
  **not been verified to pass in a real CI run** — the Azure AD app registration, federated
  credential, RBAC scoping, and GitHub secrets it depends on are deliberately not provisioned
  here (that's real Azure access, not something to generate unilaterally). See
  [`docs/04`](docs/04-guardrails-policy-as-code.md) for the exact remaining setup and why this
  is "wired in, not yet confirmed working" rather than "done.")*
- **GitOps governance**: `.github/CODEOWNERS` and a PR template requiring the JML checklist.

### Roadmap / not yet implemented
- **JML requests are validated but not enforced against live cloud access yet.** Merging a
  joiner/mover/leaver request only updates `identities/users.yaml` — no Terraform resource in
  any of the three modules manages per-user group/role membership, so a leaver merge does not
  revoke any real access anywhere. See [`docs/03-joiner-mover-leaver.md`](docs/03-joiner-mover-leaver.md)
  for the full detail. This is the most consequential gap in the project today — closing it
  (reconciling `desired_memberships_by_persona` into real membership) matters more than anything
  else on this list.
- An access-request → JSON conversion step (analogous to `policy_input_from_plan.py`) so the
  break_glass-via-joiner/mover Rego rules stop being dormant and actually evaluate real requests.
- Provision the Azure-side setup `policy-ci.yml`'s new `azure/login` step depends on (app
  registration, federated credential, read-only RBAC scope, Graph API permissions, GitHub
  secrets) and confirm it actually passes in a real CI run — the workflow YAML is wired in, but
  unverified end-to-end. See [`docs/04`](docs/04-guardrails-policy-as-code.md) for the exact
  steps.
- Real AWS permission boundaries (currently a permissive placeholder).
- A live deployment story for AWS/GCP — see the demo strategy note below.
- `environments/dev` and `environments/prod` are empty; only `sandbox` is populated.
- `modules/guardrails` and `modules/lifecycle` exist as empty placeholders for future work.

### Demo / deployment status
Azure is deployed and validated against a live tenant (`terraform plan`/`apply` have been run
against a real, low-privilege sandbox subscription) — but only the group/role *scaffolding*:
verified directly from committed plan evidence (`evidence/inventory/tfplan-20260220-170538.json`),
the only resources ever actually applied are one resource group, six role assignments, and five
Entra ID groups (one per persona, including `break_glass`'s). No user was ever added to or
removed from a persona group by Terraform, because — per the JML gap above — no resource for
that exists in the codebase yet. "Live and tested" means the scaffolding provisions correctly
against a real tenant, not that end-to-end access provisioning has been demonstrated. AWS and
GCP modules are implemented, but not deployed against live AWS/GCP accounts — a deliberate scope
decision, not an oversight. Validation depth differs between them, though: GCP's `terraform
plan` succeeds cleanly with placeholder credentials (verified, `enable_gcp=true`: `7 to add, 0
to change, 0 to destroy`, no errors); AWS's does not — `data.aws_caller_identity.current` needs
a live STS call the placeholder credentials can't satisfy, so only `terraform validate` passes
for AWS without real credentials. See [`docs/07-demo-runbook.md`](docs/07-demo-runbook.md) (to
be filled in) for how to reproduce any of this.

## How to run it locally

Requirements: Terraform >= 1.6, Python 3.11+, [conftest](https://www.conftest.dev/) (for policy
checks), and `az login` (device-code auth) if you want to touch the real Azure module.

```bash
# 1. Validate an access request change (what CI runs on PRs touching identities/)
pip install pyyaml
python scripts/validate_requests.py

# 2. Validate the Terraform config (no cloud credentials required)
cd environments/sandbox
terraform init
terraform validate

# 3. Plan against the sandbox environment (requires real Azure credentials for the
#    Azure module; set azure_subscription_id/azure_tenant_id in a local, gitignored
#    terraform.tfvars — do not hardcode them)
terraform plan

# 4. Run the policy-as-code check (what CI runs on PRs touching environments/modules/policy).
#    Must be run from inside environments/sandbox -- the script assumes that cwd, it doesn't
#    cd there itself.
bash ../../scripts/run_policy_checks.sh sandbox

# 5. Run the Rego unit tests directly (no Terraform plan or cloud credentials needed --
#    these mock their own input)
conftest verify -p policy/rego
```

Note: step 4 currently fails at the `terraform plan` stage without live Azure credentials — see
the policy-as-code caveat above. Verified by actually running it, not assumed. Step 5 (the test
suite) runs standalone and doesn't depend on step 4 completing.

## Repository layout

```
identities/            Source of truth: users, personas, access requests (joiner/mover/leaver)
environments/          Per-environment Terraform root modules (sandbox populated; dev/prod empty)
modules/               azure-iam, aws-iam, gcp-iam (implemented); guardrails, lifecycle (empty)
policy/                Rego guardrail policies, evaluated against terraform plan output
scripts/                validate_requests.py, policy_input_from_plan.py, evidence export scripts
evidence/               Generated audit artifacts (plan/output/privileged-access exports)
docs/                   Architecture, persona model, JML flow, guardrails, evidence, demo runbook
.github/                CODEOWNERS, PR template, CI workflows (requests-ci, policy-ci)
```
