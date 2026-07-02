# Joiner / Mover / Leaver flow

This describes the actual, enforced JML flow — what `scripts/validate_requests.py` and
`policy/rego/iam.rego` really check today, not an idealized version of it.

## The most important thing to understand first

**Merging a joiner, mover, or leaver request does not, by itself, grant or revoke any real
cloud access.** It updates `identities/users.yaml`. That's it. Verified by tracing every module:
- `modules/azure-iam` creates one Entra ID group per persona and assigns cloud roles *to those
  groups* — but there is no resource anywhere that adds or removes individual users as members
  of a group.
- `modules/gcp-iam` binds a persona's cloud role to a Google Group *by email* — but nothing in
  this repo manages who belongs to that Google Group.
- `modules/aws-iam` creates one IAM role per persona, assumable by any principal in the AWS
  account (the trust policy trusts the account root, not specific users) — it isn't scoped to
  individual people at all.
- `environments/sandbox/main.tf` does compute `desired_memberships_by_persona` — the set of
  active users who *should* be in each persona's group, derived from `users.yaml` — but it's
  only exposed as a debug Terraform output today, not consumed by anything that reconciles it
  into actual group membership.

So today, the JML flow is a **validated, auditable paper trail**: it guarantees that the request
is well-formed, that the persona is real, that break_glass can't be requested this way, and that
`users.yaml` stays internally consistent. It does not yet guarantee that a leaver's access is
actually removed anywhere. Closing that gap — reconciling `desired_memberships_by_persona` (or
its equivalent) into real group/role membership — is the single most important missing piece for
this project to be more than a request-tracking system, and belongs on the roadmap ahead of
almost everything else in `docs/04`/`docs/05`.

## Common fields (all three request types)

Every request YAML under `identities/access-requests/{joiner,mover,leaver}/` must have:
`request_type` (`joiner`|`mover`|`leaver`), `request_id`, `requested_by`, `requested_at`, a
`user` object, and `justification`. Missing any of these fails validation immediately, before
any type-specific checks run. `user.email` must contain `@`; there's no stronger format check
than that. Files named `_TEMPLATE*.yaml` (one per directory) are explicitly skipped — they exist
as copy-paste starting points, not real requests.

## Joiner

Required on `user`: `email`, `display_name`, `persona`, `status`.

Rejected when:
- `persona` isn't a key in `identities/personas.yaml` (currently:
  `security_analyst`, `cloud_engineer`, `auditor`, `devsecops_engineer` — see
  [`docs/02`](02-personas-rbac-model.md) for why `break_glass` isn't in that list).
- `email` already exists in `identities/users.yaml` (joiners must be new).

There is also a dedicated `if persona == "break_glass": fail(...)` check in the code, with its
own message ("joiner cannot request break_glass. Use a dedicated emergency process.") — but
because `break_glass` was never a valid persona key to begin with, a request naming it is always
rejected one check earlier, by "unknown persona." The dedicated break_glass message is currently
unreachable. See [`docs/02`](02-personas-rbac-model.md#break-glass-isolation-whats-actually-live-vs-designed-but-dormant)
for the full trace.

## Mover

Required on `user`: `email`, `new_persona`.

Rejected when:
- `new_persona` isn't a valid persona key (same list as joiner, same `break_glass` caveat —
  a mover requesting `break_glass` is rejected as "unknown new_persona," not by the dedicated
  mover break_glass message, for the same reason as above).
- `email` does *not* already exist in `identities/users.yaml` (movers must already be a user —
  the inverse of the joiner check).

Note that a mover request only changes which persona a user is mapped to in `users.yaml` — it
doesn't (yet) touch which cloud groups/roles they're actually in, for the same reason described
above.

## Leaver

Required on `user`: `email`, `termination_date` (format is not validated beyond being present —
no `YYYY-MM-DD` format check is actually enforced, despite what the field name and template
suggest). The template also includes a `reason` field (e.g. `"Offboarding"`), but it is not
checked by the validator at all — it can be omitted, misspelled, or nonsensical and the request
still passes.

Rejected when:
- `email` does not already exist in `identities/users.yaml`.
- `termination_date` is missing.

As covered above: a leaver request passing validation and being merged does not currently cause
any access to be revoked. It updates the user's presence/status in `users.yaml`; actually
removing them from Azure groups, AWS role trust, or GCP group membership is not automated today.

## Policy-as-code layer (`policy/rego/iam.rego`)

The Rego policy has rules that mirror the Python validator's `break_glass` checks (`kind ==
"access_request"`, `request_type == "joiner"`/`"mover"`, persona/new_persona ==
`"break_glass"`) — these are intended as an independent, request-shaped backstop. In practice
they are never invoked: nothing in this repo's CI or scripts converts an access-request YAML
file into the JSON shape those rules expect — proven directly by a dormancy test in
`policy/rego/iam_test.rego`, not just asserted. `policy/rego/iam.rego`'s other two rules (deny
Azure `Owner`, deny AWS `AdministratorAccess`) operate on Terraform plan output, not the request
YAML — so they'd only catch a break_glass-shaped over-grant if and when it showed up in a real
`terraform plan`, not at request-review time. As of the Phase 3 policy-as-code pass, they're now
genuinely live: `scripts/run_policy_checks.sh`'s `conftest` invocation was previously missing
`--all-namespaces` and silently evaluated zero rules (fixed), and `scripts/policy_input_from_plan.py`
now correctly exempts the legitimate `break_glass` grant instead of flagging it as a violation
(also fixed). Full detail and the verification trail in
[`docs/02`](02-personas-rbac-model.md#break-glass-isolation-whats-actually-live-vs-designed-but-dormant).

## What a break_glass request actually looks like today

There is no supported way to request `break_glass` through the joiner/mover flow — by design,
per CLAUDE.md, even if the specific mechanism currently doing the rejecting (the generic
"unknown persona" check, rather than the dedicated message) isn't the one the code comments
suggest. There is also no documented alternative process yet — `identities/personas.yaml`
doesn't register `break_glass`, and no runbook describes what the "dedicated emergency process"
the error messages refer to actually is. That's tracked as a gap for
[`docs/04-guardrails-policy-as-code.md`](04-guardrails-policy-as-code.md) and
[`docs/05-access-reviews-audit-evidence.md`](05-access-reviews-audit-evidence.md).
