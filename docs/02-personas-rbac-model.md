# Persona / RBAC model

Five personas exist in the system. Four are declared in `identities/personas.yaml`; the fifth
(`break_glass`) is not declared there at all. It's fully wired through every Terraform module,
and there's code intended to guard against it in both `scripts/validate_requests.py` and
`policy/rego/iam.rego` — but as detailed below, only one of those guards is actually live today.
This table is cross-checked against the actual persona-to-role locals in
`environments/sandbox/main.tf`, not just against what `personas.yaml` says — the two don't
always agree, and the disagreements are called out below rather than smoothed over.

## The table

| Persona | `personas.yaml` description | Declared privilege level | Azure role | AWS policy | GCP role |
|---|---|---|---|---|---|
| `security_analyst` | Responsible for security handling of the project | High | `Reader` | `ReadOnlyAccess` | `roles/viewer` |
| `auditor` | Performs compliance and access reviews | Low | `Reader` | `SecurityAudit` | `roles/viewer` |
| `cloud_engineer` | Builds and operates cloud infrastructure | Medium | `Contributor` | `PowerUserAccess` | `roles/editor` |
| `devsecops_engineer` | Manages CI/CD and security automation | Medium | `Contributor` | `PowerUserAccess` | `roles/editor` |
| `break_glass` | *(not declared in personas.yaml — see below)* | — | `Owner` | `AdministratorAccess` | `roles/owner` |

Source: `environments/sandbox/main.tf` locals `azure_persona_to_role`,
`aws_persona_to_policy_arns`, `gcp_persona_to_role` — the single place all three cloud mappings
are centralized (see [`docs/01-architecture.md`](01-architecture.md)).

## Where the table and the declared intent disagree

Three distinct findings here, deliberately not lumped together — they don't carry the same
weight or call for the same fix.

- **`security_analyst`/`auditor` identical RBAC — a labeling/documentation issue, not
  under-scoping.** Both get read-only access (`Reader`/`ReadOnlyAccess`/`roles/viewer`).
  Granting `security_analyst` *more* than that to match its "High" label would actually violate
  this project's own least-privilege-by-default principle — read-only is the safe, correct
  choice here, not a gap to close. The actual problem is that `personas.yaml`'s
  `privilege_level` field doesn't define what axis it measures (write capability? information
  sensitivity? something else?), so labeling `security_analyst` "High" next to an
  identical-to-`auditor` RBAC mapping reads as inconsistent. The fix is to clarify or correct
  the label, not to change the Terraform mapping — this is not a roadmap/implementation item.
- **`cloud_engineer`/`devsecops_engineer` identical RBAC — a real scope gap, roadmap-worthy.**
  Two personas with genuinely distinct declared responsibilities ("create and manage cloud
  resources" vs. "manage pipelines and service identities") currently collapse to identical
  permissions (`Contributor`/`PowerUserAccess`/`roles/editor`) in all three clouds. This isn't a
  security risk either way — both already sit at an appropriately-scoped, non-admin tier — but
  it does mean the persona model's promised five-way granularity is actually only three distinct
  permission tiers today. Tracked on the roadmap: either differentiate their actual grants in a
  future phase, or explicitly decide to collapse them into one persona.
- **`break_glass` isn't a real entry in `identities/personas.yaml` — verified unreachable code,
  but likely an oversight, not a deliberate isolation mechanism.** Tracing the actual control
  flow in `scripts/validate_requests.py`: `persona_keys` is built from `personas.yaml`'s dict
  keys, which excludes `break_glass`. Any joiner request naming it fails at
  `if persona not in persona_keys` — which calls `fail()` → `sys.exit(1)` — before execution
  ever reaches the dedicated `if persona == "break_glass": fail(...)` line below it. That line
  is unreachable today; this is a fact about the current code path, not a guess. Whether the
  `personas.yaml` omission itself was *intentional*, though, is a separate question — and the
  evidence points the other way: nothing documents the omission as deliberate, the Terraform
  locals treat `break_glass` as a first-class persona everywhere else in the system, and the
  code comment above the dead line ("v1 guardrail: break_glass cannot be assigned via joiner
  request") reads like the author expected that specific check to be the thing doing the
  blocking. What *is* clearly deliberate, per CLAUDE.md, is the outcome — break_glass must never
  be assignable via joiner/mover — just not this particular path to it. The safety property
  holds today regardless (the request is still rejected, just via the "unknown persona" branch
  instead), but the `personas.yaml` gap and the resulting dead code are best read as an
  oversight worth cleaning up, not a designed defense-in-depth layer.

## Break-glass isolation: what's actually live vs. designed but dormant

Unlike the other four personas, `break_glass` is *currently* never assignable through the normal
joiner/mover request flow — but tracing exactly how reveals only one of the intended layers is
actually doing the work today:

1. **Live**: `scripts/validate_requests.py`'s "unknown persona" check rejects it, as a side
   effect of `break_glass` being absent from `personas.yaml` (see above) — not via its own
   dedicated `if persona == "break_glass"` check, which is unreachable.
2. **Not live — no input producer exists.** `policy/rego/iam.rego` has two rules gated on
   `input.kind == "access_request"` (one for joiner, one for mover) that are clearly *meant* to
   independently deny `break_glass` requests, evaluated against the request itself rather than
   the Python validator's logic. But nothing in this repo's pipeline ever produces JSON shaped
   that way: `scripts/policy_input_from_plan.py` — the only thing that ever feeds `conftest` —
   exclusively emits `{address, resource_type, values, meta}` objects derived from a Terraform
   plan's `resource_changes`, never anything derived from
   `identities/access-requests/*.yaml`. Verified by grepping the entire `scripts/`, `policy/`,
   and `.github/` trees for any producer of `kind`-shaped input: none exists. These two rules
   are dormant, not dead in the same sense as (1) — they're reachable in principle, just never
   invoked with real input.
3. The other two rules in `iam.rego` (deny Azure `Owner`, deny AWS `AdministratorAccess`) *are*
   live — their input shape matches what `policy_input_from_plan.py` actually produces, so they
   would independently catch a `break_glass`-style over-grant surfacing as a Terraform-plan
   change, even without referencing the persona name at all.

Net effect: today, break_glass protection rests on one live mechanism (the accidental
"unknown persona" rejection) plus one structurally-independent, genuinely-live backstop (the
Owner/AdministratorAccess role-level denies, which don't need to know about personas at all to
catch a break_glass-shaped over-grant). The two rules that were clearly *designed* to be a
second, request-shaped check on the persona name specifically are present in the code but never
exercised. This is worth fixing (add an access-request → JSON conversion step, analogous to
`policy_input_from_plan.py`, and wire it into `run_policy_checks.sh` or a new script) rather than
just documented — tracked on the roadmap.

It's also implemented differently in the Terraform modules themselves, not just gated by
convention: Azure's break-glass role assignment (`modules/azure-iam/main.tf`) is excluded from
the per-persona `for_each` loop and created as its own explicit resource; AWS's break-glass role
(`modules/aws-iam/main.tf`) gets a 900-second `max_session_duration` instead of the standard
3600 seconds, so even if it were ever assumed, the session is short-lived by design.

There is currently no formal onboarding path for `break_glass` at all (by design — it's meant to
be a dedicated emergency process, not a joiner/mover request), and no documented runbook yet for
what that process actually is. That's tracked as a gap for
[`docs/04-guardrails-policy-as-code.md`](04-guardrails-policy-as-code.md) /
[`docs/05-access-reviews-audit-evidence.md`](05-access-reviews-audit-evidence.md), once those are
filled in.
