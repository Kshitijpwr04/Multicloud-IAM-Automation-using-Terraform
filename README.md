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
- **GCP module** (`modules/gcp-iam`): automation + CI/CD service accounts, persona-based project
  IAM bindings via Google Groups. Code-complete and passes `terraform validate`, but gated off by
  default (`enable_gcp = false`) and never `plan`/`apply`-tested against a real GCP project
  (`gcp_project_id` still defaults to a placeholder).
- **Identity source of truth**: `identities/users.yaml`, `identities/personas.yaml`.
- **Request validation**: `scripts/validate_requests.py` — enforces persona validity, blocks
  `break_glass` via joiner/mover, checks joiner/leaver preconditions. Wired into CI
  (`requests-ci.yml`).
- **Evidence export**: `scripts/inventory/*.sh` generate Terraform output/plan/privileged-access
  JSON into `evidence/`.
- **Policy-as-code (partial)**: `policy/rego/iam.rego` implements the same guardrails as the
  Python validator, but evaluated against the Terraform plan JSON, and it's wired into CI
  (`policy-ci.yml` runs it via `conftest`). What's missing: `policy/opa/` and `policy/conftest/`
  are still empty — there's no test suite proving the Rego rules actually catch violations.
  *(Caveat: `policy-ci.yml` has no Azure authentication step — no `azure/login`, no `ARM_*`
  credentials — so its `terraform plan` step has no credential path on a fresh GitHub Actions
  runner and hasn't been verified to pass end-to-end in CI; this predates this rebuild pass.)*
- **GitOps governance**: `.github/CODEOWNERS` and a PR template requiring the JML checklist.

### Roadmap / not yet implemented
- Conftest test cases for the guardrail policies (the part that makes policy-as-code credible).
- An Azure credential path for `policy-ci.yml` (`azure/login` or `ARM_*` secrets) so the policy
  check's `terraform plan` step can actually complete on a GitHub Actions runner.
- Real AWS permission boundaries (currently a permissive placeholder).
- A live deployment story for AWS/GCP — see the demo strategy note below.
- `environments/dev` and `environments/prod` are empty; only `sandbox` is populated.
- `modules/guardrails` and `modules/lifecycle` exist as empty placeholders for future work.

### Demo / deployment status
Azure is deployed and validated against a live tenant (`terraform plan`/`apply` have been run
against a real, low-privilege sandbox subscription). AWS and GCP modules are implemented and
validated via `terraform validate`/`plan` with placeholder credentials, but not deployed against
live AWS/GCP accounts. This is a deliberate scope decision, not an oversight — see
[`docs/07-demo-runbook.md`](docs/07-demo-runbook.md) (to be filled in) for how to reproduce it.

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
```

Note: step 4 currently fails past the `terraform plan` stage without live Azure credentials —
see the policy-as-code caveat above. Verified by actually running it, not assumed.

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
