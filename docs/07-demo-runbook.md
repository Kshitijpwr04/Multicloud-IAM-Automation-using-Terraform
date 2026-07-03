# Demo runbook

Literal, copy-pasteable steps to reproduce what's actually real today. Every command below has
been re-run and verified while writing this doc — none of this is aspirational, and none of it
is presented as uniformly smooth. Where a step has a real, known limitation, it's cited by
commit/finding rather than glossed over.

## Prerequisites

- Terraform >= 1.6
- Python 3.11+ with `pyyaml` (`pip install pyyaml`)
- [`conftest`](https://www.conftest.dev/) 0.54.0+ (match your architecture — the ARM64 build is
  `conftest_<version>_Linux_arm64.tar.gz`, not the `_x86_64` one CI installs)
- `az` CLI, only needed for step 3 (the one live cloud path)

## 1. Validate an access request

No credentials needed — this only reads `identities/*.yaml` and
`identities/access-requests/**/*.yaml`.

```bash
python scripts/validate_requests.py
```

**Success** looks like:
```
[OK] Request files validated (joiner/mover/leaver).
```
(exit code 0)

**Failure** looks like a specific, actionable reason and a non-zero exit — for example, this is
what it printed earlier in this rebuild pass, before a stale example request was fixed
(commit `7732c1f`):
```
[FAIL] identities/access-requests/mover/MR-0001-example.yaml: mover user not found in users.yaml: kshitijpawar04@gmail.com
```
(exit code 1). Every failure mode prints `[FAIL] <file>: <specific reason>` — there's no vague
"validation failed" output.

## 2. `terraform validate` across all three modules

Also no credentials needed — `validate` is a structural/type check, it never contacts a cloud
provider. This one command covers the Azure, AWS, and GCP modules together (they're all wired
into the same root module, `environments/sandbox`):

```bash
cd environments/sandbox
terraform init
terraform validate
```

**Success**:
```
Success! The configuration is valid, but there were some
validation warnings as shown above.
```
The warnings are pre-existing and harmless — `aws_iam`/`gcp_iam`'s provider-passthrough
declarations, not errors. `Success!` with exit code 0 either way.

## 3. Azure: `terraform plan` (and optionally `apply`) against the real sandbox

**This is the only one of the three clouds with a live deployment path.** Requires:

```bash
az login   # device-code auth, against the tenant you're targeting
```

Then create a local, gitignored `terraform.tfvars` in `environments/sandbox/` (never commit
this, never default these in `variables.tf` — see the Phase 0 fix, commit `5f740a8`):
```hcl
azure_subscription_id = "<your real subscription id>"
azure_tenant_id        = "<your real tenant id>"
```

```bash
cd environments/sandbox
terraform plan
terraform apply
```

This is what actually produced the resources documented in `evidence/`: one resource group, six
role assignments, five Entra ID groups (one per persona, including `break_glass`'s) — see
[`docs/01-architecture.md`](01-architecture.md) for the full breakdown, verified directly from
plan evidence, not assumed. **It does not add or remove any user from those groups** — no
Terraform resource in this repo manages per-user group membership. See the caveat in
[`docs/03-joiner-mover-leaver.md`](03-joiner-mover-leaver.md#the-most-important-thing-to-understand-first)
before treating an `apply` here as granting anyone real access.

## 4. GCP: targeted plan only

```bash
cd environments/sandbox
TF_VAR_azure_subscription_id="00000000-0000-0000-0000-000000000000" \
TF_VAR_azure_tenant_id="11111111-1111-1111-1111-111111111111" \
TF_VAR_enable_aws=false \
TF_VAR_enable_gcp=true \
TF_VAR_gcp_project_id="test-project-id" \
terraform plan -target=module.gcp_iam
```

**Success**:
```
Plan: 7 to add, 0 to change, 0 to destroy.
```
No real GCP credentials needed — unlike AWS (step 5), GCP's module has no data source that
requires live authentication, so a fake project ID is enough for a clean plan. The fake Azure
IDs above are only there to satisfy variable validation for the rest of the (untargeted) config;
they're not touched by the targeted GCP plan itself.

This specific command is also what first caught a real bug: before commit `03933e1` (Phase 2),
running exactly this — `enable_gcp=true` had never actually been tried — failed with
`module.gcp_iam is tuple with 1 element — this value does not have any attributes`, because two
root outputs referenced `module.gcp_iam.<attr>` without the `[0]` index its `count`-based
instantiation requires. Fixed and reverified; the command above is the regression check.

## 5. AWS: `terraform validate` only — `plan` does not work with placeholders

```bash
cd environments/sandbox
terraform validate
```
Passes (same command/output as step 2 — it's one shared config).

**Don't expect `terraform plan` to also succeed here the way it does for GCP.** Confirmed by
running it:
```bash
TF_VAR_azure_subscription_id="00000000-0000-0000-0000-000000000000" \
TF_VAR_azure_tenant_id="11111111-1111-1111-1111-111111111111" \
TF_VAR_enable_aws=true \
TF_VAR_enable_gcp=false \
terraform plan -target=module.aws_iam
```
fails with:
```
Error: reading STS Caller Identity
  with module.aws_iam[0].data.aws_caller_identity.current
  ... InvalidClientTokenId: The security token included in the request is invalid.
```
`modules/aws-iam/main.tf`'s `data.aws_caller_identity.current` makes a live STS call to build
the trust-policy ARN — not covered by the provider's `skip_credentials_validation`/
`skip_requesting_account_id` flags, which only suppress the *provider's own* implicit lookup,
not this explicit `data` block. This is the Phase 5 correction (commit `3c5757d`): AWS and GCP
are not equally "plan-validated with placeholders," and this doc won't repeat that claim.

## 6. Policy-as-code: `run_policy_checks.sh` and the Conftest test suite

Two different things, two different credential requirements.

**The full pipeline check** — requires live Azure credentials, same as step 3, and **must be run
from inside `environments/sandbox`** (the script assumes that working directory; it doesn't `cd`
there itself):
```bash
cd environments/sandbox
bash ../../scripts/run_policy_checks.sh sandbox
```
Without live Azure credentials, this fails at the `terraform plan` step — not a new limitation,
the same one as step 3. Note also: `.github/workflows/policy-ci.yml` has no Azure credential
path configured at all (no `azure/login`, no `ARM_*` secrets), so this check cannot currently
complete on a fresh GitHub Actions runner either — see
[`docs/04-guardrails-policy-as-code.md`](04-guardrails-policy-as-code.md) for the full detail on
why "a violating PR fails automatically" isn't fully true yet.

**The Rego/Python test suites** — no credentials needed at all, since they mock their own input:
```bash
conftest verify -p policy/rego
```
Expected: `12 tests, 12 passed, 0 warnings, 0 failures, 0 exceptions, 0 skipped`. This includes a
test proving the break_glass-via-joiner/mover rules are *dormant* against real captured pipeline
output — see [`docs/04`](04-guardrails-policy-as-code.md) for why, and don't expect this test
count to imply those rules are enforced end-to-end.

```bash
python3 scripts/test_policy_input_from_plan.py
```
Expected: `All 6 cases passed.` Proves the break_glass address-matching logic (commit
`544bf3d`) resists 3 forged address patterns, not just the 2 real grants.

## 7. Generate evidence via the inventory scripts

```bash
bash scripts/inventory/export_tf_outputs.sh
bash scripts/inventory/export_privileged_report.sh
```
Neither needs live credentials — both read local Terraform state, not a live plan. Known gap in
the second one: it checks for GCP privileged roles under `google_project_iam_binding`, but
`modules/gcp-iam` creates `google_project_iam_member`, so it can never match a GCP entry (see
[`docs/01`](01-architecture.md)) — doesn't affect current output since GCP isn't deployed, but
would matter the moment it is.

```bash
bash scripts/inventory/export_policy_inventory.sh
```
**Requires** live Azure credentials — runs a real `terraform plan` internally, same limitation
as step 3.

If you regenerate any of these against a real subscription: scrub real subscription/tenant IDs
(and any other real object IDs) **before** the file ever touches this repo, not after — see the
Phase 0 and Phase 6 evidence commits for the exact mapping approach used so far. Never commit
real IDs even temporarily.

## What this demo does not show

- Any real per-user access grant or revocation — see
  [`docs/03`](03-joiner-mover-leaver.md#the-most-important-thing-to-understand-first) and
  [`docs/05-access-reviews-audit-evidence.md`](05-access-reviews-audit-evidence.md). What's
  demonstrated is infrastructure-level: groups exist, roles are assigned to groups, break_glass
  is isolated. Not: "user X can currently do Y."
- A PR that violates a guardrail failing automatically in real GitHub Actions (step 6's
  caveat) — the policy logic and tests are real and correct; the CI credential path to reach
  them isn't.
- A live GCP or AWS deployment — both are implemented, and validated to different depths (GCP:
  `plan`-clean with placeholders; AWS: `validate`-clean only, per step 5) — neither is deployed
  against a real account. Deliberate scope decision (Phase 5), not an oversight.
