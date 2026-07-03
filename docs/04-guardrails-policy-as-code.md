# Guardrails / policy-as-code

The guardrails exist and are tested, but the honest headline is: **automatic PR enforcement is
not fully wired up yet.** This document covers what the policy actually checks, two real bugs
that made it a no-op until this rebuild pass, and exactly what's still missing before "a PR that
violates a guardrail fails automatically" is true.

## The rules (`policy/rego/iam.rego`)

Four `deny` rules, package `iam.guardrails`:

1. Deny any `azurerm_role_assignment` with `role_definition_name == "Owner"`, unless
   `meta.allow_owner` is true.
2. Deny any `aws_iam_role_policy_attachment` with `policy_arn` ==
   `arn:aws:iam::aws:policy/AdministratorAccess`, unless `meta.allow_admin` is true.
3. Deny a joiner access-request (`input.kind == "access_request"`,
   `input.request_type == "joiner"`) naming `persona == "break_glass"`.
4. Deny a mover access-request naming `new_persona == "break_glass"`.

Rules 1–2 operate on Terraform plan data (fed by `scripts/policy_input_from_plan.py`). Rules
3–4 operate on access-request YAML data — but nothing in this repo converts an access-request
file into the shape they expect, so they're currently dormant (see below).

## Bug #1: the entire check was a no-op, independent of CI credentials

`scripts/run_policy_checks.sh` ran `conftest test policy-input.json -p ../../policy/rego --data
"$DATA_FILE"` — no `--namespace`/`--all-namespaces` flag. Conftest defaults to namespace `main`;
this policy declares `package iam.guardrails`. Without the flag, conftest silently evaluates
**zero** rules and exits 0 regardless of input. Verified by reproducing the exact invocation
against real data containing an actual `Owner` grant:

```
$ conftest test policy-input.json -p policy/rego --data policy/rego/data.json
0 tests, 0 passed, 0 warnings, 0 failures, 0 exceptions
exit code: 0
```

Re-running with `--all-namespaces` added correctly evaluated 24 checks and caught the violation.
Fixed by adding the flag. This means the policy check had never actually caught anything, ever,
for a reason unrelated to CI infrastructure — it just wasn't looking.

## Bug #2: fixing #1 immediately false-positived on the real break_glass grant

Once namespace targeting worked, the check immediately failed on the legitimate, already-deployed
`break_glass` → `Owner` role assignment — `policy_input_from_plan.py` hardcoded
`meta.allow_owner`/`allow_admin` to `false` for every entry, with no concept of exceptions.

## The break_glass exemption, and how it's scoped

Fixed by computing `allow_owner`/`allow_admin` per-resource in `policy_input_from_plan.py`,
based on the Terraform resource address — but the first version of this fix
(`is_break_glass = "break_glass" in addr`) was a bare substring match, and **exploitable**: any
resource or module renamed to contain that word anywhere in its address would be exempted,
regardless of what it actually granted or to whom. Confirmed with three concrete forged
addresses (a relabeled Azure resource, a renamed module, a differently-labeled AWS resource
reusing the `break_glass::` key prefix) — all three slipped past the loose check.

Tightened to anchor on the *specific* resource construct each module actually uses for its
break_glass persona:
- Azure: the address must end with `.azurerm_role_assignment.break_glass_owner` — a single,
  uniquely labeled resource, not a `for_each`.
- AWS: the address must contain `.aws_iam_role_policy_attachment.persona["break_glass::` —
  checking both the resource label (`persona`) and the `for_each` key prefix, so a
  differently-labeled resource can't forge the key.

Tested at two independent levels:
- `scripts/test_policy_input_from_plan.py` tests the matching function (`is_break_glass`)
  directly against 2 real grants, 1 real unrelated grant, and all 3 forged addresses — proving
  the matching logic itself resists spoofing. Verified this test catches a regression by
  temporarily reverting to the old loose check and confirming exactly the 3 forged cases failed.
- `policy/rego/iam_test.rego` proves the Rego `deny` rule correctly denies an Owner grant on a
  forged-looking address, *given* the correct (post-fix) `meta.allow_owner: false` — but this
  only proves the Rego layer trusts `meta` correctly, since Rego never inspects the address
  itself. The address-matching guarantee lives entirely in the Python test above.

## The dormant break_glass-via-JML rules

Rules 3–4 (deny break_glass via joiner/mover) require input shaped like
`{"kind": "access_request", "request_type": "joiner", "user": {"persona": "break_glass"}}`.
Nothing in this repo produces that shape — `policy_input_from_plan.py` only ever emits
Terraform-plan-derived records. `policy/rego/iam_test.rego` has a dedicated test
(`test_real_pipeline_output_never_has_a_kind_field`) that feeds the rules a real captured sample
of `policy_input_from_plan.py`'s actual output and proves none of it has a `kind` field — making
the dormancy directly provable rather than an assertion. In practice, the only thing currently
stopping a joiner/mover request from naming `break_glass` is
`scripts/validate_requests.py`'s generic "unknown persona" check (a side effect of `break_glass`
being absent from `identities/personas.yaml`, not a dedicated check — see
[`docs/02`](02-personas-rbac-model.md#break-glass-isolation-whats-actually-live-vs-designed-but-dormant)).
Closing this gap for real requires a new script (an access-request → JSON converter, analogous
to `policy_input_from_plan.py`) wired into CI — a feature, not something a test suite closes.

## Honest state of CI enforcement

`.github/workflows/policy-ci.yml` runs `scripts/run_policy_checks.sh` on PRs touching
`environments/`, `modules/`, `policy/`, or `scripts/`. With both bugs above fixed, the logic is
sound and tested.

**The workflow now has a credential path (as of this commit), but it has not been verified to
pass in a real CI run.** It adds `azure/login@v2` using OIDC/federated login — `client-id`,
`tenant-id`, `subscription-id` read from GitHub repo secrets (`AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`), no long-lived client secret — plus
`permissions: id-token: write` and the matching `TF_VAR_azure_subscription_id`/
`azure_tenant_id` env vars for Terraform. This was deliberately **not** verified end-to-end:
provisioning the actual Azure AD app registration, its federated credential trust, and its RBAC
scoping is real Azure access that shouldn't be created unilaterally — that setup is the repo
owner's to do. Until it exists, this step will fail authentication exactly like it did before,
just at a different point (an actual login failure instead of no login attempt at all).
Validated so far only via local YAML parsing and reasoning about the `azure/login` + Terraform
provider auth chain — not an actual GitHub Actions execution.

What still needs to happen on the Azure/GitHub side before this passes for real (full detail
given directly to the repo owner, summarized here):
1. An Azure AD app registration with a federated credential trusting this repo's `pull_request`
   workflow specifically (the OIDC subject claim differs for PR-triggered vs. branch-triggered
   runs).
2. An Azure RBAC role assignment scoped to **read-only**, ideally just on the `rg-iam-sandbox`
   resource group — not the broad access an interactive `az login` session has, and not
   subscription-wide.
3. Microsoft Graph API permissions on the app registration (e.g. `Group.Read.All`, admin
   consent required) — the `msgraph` provider needs its own auth path, separate from the
   `azurerm` provider's RBAC role above, since `terraform plan` also touches
   `msgraph_resource.persona_group`.
4. The three GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) added
   to the repo.

**So: "a PR that would violate a guardrail fails automatically" is closer, but still not
verified true end-to-end.** The policy logic is correct and tested (Rego + Python). The
workflow now has a credential path wired in. What's unverified is whether that credential path
actually authenticates successfully once the Azure-side setup above exists — that requires a
real CI run this session cannot produce.
