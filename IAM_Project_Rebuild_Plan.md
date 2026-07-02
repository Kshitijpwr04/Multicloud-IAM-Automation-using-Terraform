# Multi-Cloud IAM Automation — Rebuild Plan & Claude Code Kickoff Brief

## Decision: refactor, don't restart

A full restart throws away real, working code: the Azure module (Entra ID groups, RBAC,
break-glass isolation), the persona/user YAML model, `validate_requests.py` (genuinely solid),
and the evidence-export scripts. None of that needs to be rewritten. What's broken is:
scope honesty (docs claim more than exists), a few structural bugs, and three missing pieces
(GCP module, OPA policies, GitOps governance files).

Treat this as a **refactor-and-complete** pass, not a rewrite.

---

## Phase 0 — Security & hygiene (do this before anything else, ~30 min)

- [x] Remove hardcoded `azure_subscription_id` and `azure_tenant_id` defaults from
      `environments/sandbox/variables.tf`. Replace with no default (required var) and
      document that real values go in a local `terraform.tfvars` file.
- [x] Add `terraform.tfvars` and `*.auto.tfvars` to `.gitignore` (currently missing).
      Also added patterns for local `tfplan*`/`tfstate.json`/`policy-input.json` artifacts
      found littering `environments/sandbox/` untracked, and deleted the stray copies.
- [x] Check git history for whether those real IDs were committed in earlier commits —
      confirmed: introduced at commit `b02b597` and present in every commit since, plus
      embedded in ~18 already-committed evidence JSON files under `evidence/demo/` and
      `evidence/inventory/`. Not rotating (not usually necessary for sandbox tenant/sub IDs);
      regenerating the evidence artifacts is deferred to Phase 6.
- [x] Fix `scripts/inventory/export_policy_inventory.sh` — it was calling
      `scripts/policy_input_from_plan.py` with no argument, which hardcoded reading a plan
      file literally named `tfplan`, while the shell script generates a timestamped
      `tfplan-${TS}`. Fixed by having `policy_input_from_plan.py` accept an explicit
      plan-JSON path argument, and the shell script now passes the timestamped path it
      just generated.

## Phase 1 — Ground the docs in reality (~1–2 hrs)

Write these now, based on what's *actually implemented today*, not the aspirational
Phase 1–10 plan. It's fine — good, even — for a README to have a clearly labeled
"Roadmap / Not Yet Implemented" section. That reads as maturity, not incompleteness.

- [ ] `README.md`: problem statement, architecture diagram (ASCII or image), what's
      implemented vs. roadmap, how to run it locally, screenshot/GIF if possible.
- [ ] `docs/01-architecture.md`: the Identity YAML → Git → CI validation → Terraform →
      Cloud → Evidence flow, with a real diagram.
- [ ] `docs/02-personas-rbac-model.md`: the persona table, cleaned up (fix the typos in
      `identities/personas.yaml` while you're there — "Resposible", "proejct", "aprivileged").
- [ ] `docs/03-joiner-mover-leaver.md`: describe the actual JML flow the validator enforces.
- [ ] Leave `docs/04` and `docs/05` (guardrails, access reviews) as stubs with a one-line
      "planned in Phase X" note until Phase 3/4 below are done — then fill them for real.

## Phase 2 — Finish the GCP module (~2–4 hrs)

Bring `modules/gcp-iam` to parity with `aws-iam`/`azure-iam` so `terraform plan` in
`environments/sandbox` actually succeeds. Needs:
- `variables.tf`: `project_id`, `name_prefix`, `persona_to_role`, `persona_group_emails`
  (these are already referenced by `environments/sandbox/main.tf` — just not declared).
- `main.tf`: real resources — at minimum `google_project_iam_member` per persona/role,
  or Google Groups if you want parity with the Entra ID group pattern in Azure.
- `outputs.tf`: real outputs (not the current `gcp_module_ready = true` stub) — expose
  the resource IDs/emails other modules or evidence scripts would need.

## Phase 3 — Policy-as-Code (~3–5 hrs) — the differentiator, currently empty

This is the most interview-relevant piece and it doesn't exist yet. Build:
- [ ] `policy/opa/guardrails.rego` — deny rules: e.g. no mover request can assign
      `break_glass` (mirror the check already in `validate_requests.py` — but as an
      OPA policy over the Terraform plan JSON, not just the YAML request).
- [ ] `policy/conftest/` — Conftest test cases (`*.rego` test files) that prove the
      guardrail policy actually catches violations. Tests are what make this credible.
- [ ] Wire policy evaluation into the CI workflow so a PR that would violate a guardrail
      fails automatically — this is the "policy-as-code" payoff.

## Phase 4 — GitOps governance files (~30 min, cheap wins)

- [ ] `.github/CODEOWNERS` — require review on `identities/`, `policy/`, `modules/`.
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` — checklist referencing the JML request format.
- [ ] Move/rename so `pipelines/github-actions` isn't an empty folder sitting next to the
      real workflow in `.github/workflows/` — either populate it with docs about the
      pipeline or remove the empty folder.

## Phase 5 — Decide the demo strategy (important, decide before Phase 6)

You need a real answer to "does this actually deploy anywhere?" for the interview.
Options, roughly in order of impressiveness vs. effort:

1. **Real free-tier deploy**: Azure has a free tier, AWS has a free tier, GCP has a free
   tier. If you're willing to create throwaway accounts, a real `terraform apply` against
   a real (locked-down, budget-alerted) sandbox in all three clouds is the strongest story.
2. **Real Azure only, AWS/GCP as validated-plan-only**: You already have real Azure access
   (evidence of `terraform plan` runs exists). Be explicit in the README: "Azure is
   deployed and tested against a live tenant; AWS and GCP modules are implemented and
   validated via `terraform plan`/`validate` but not deployed against live accounts."
   This is honest and still credible — plenty of real IAM tooling is validated this way
   in CI without every engineer having live cloud access.
3. **Code-only everywhere**: weakest for interviews — avoid if you can help it.

Recommend option 2 unless you're up for spinning up AWS/GCP sandboxes too.

## Phase 6 — Evidence & docs closeout (~1 hr)

- [ ] Regenerate `evidence/inventory` and `evidence/demo` artifacts once GCP module and
      policy checks exist, so the sample evidence reflects the real, complete system.
- [ ] Fill in `docs/04-guardrails-policy-as-code.md` and `docs/05-access-reviews-audit-evidence.md`
      for real now that Phase 3 exists.
- [ ] Fill in `docs/07-demo-runbook.md` — literal step-by-step "how to run this yourself."

## Phase 7 — Blog series (after the above)

Use the phase structure itself as the outline — it maps almost directly to the "Blog Plan"
in the handoff doc:
1. Problem statement + architecture
2. Identity-as-code / persona model
3. Multi-cloud implementation (what was easy, what wasn't — the AWS permission-boundary
   placeholder issue and the Azure Graph-vs-AzureAD provider decision are good, honest
   "here's what I learned" material)
4. GitOps workflow
5. Policy-as-Code with OPA/Conftest
6. Evidence generation for audit-readiness
7. Lessons learned / what's still on the roadmap

---

## How to run this with Claude Code

Paste the prompt below into Claude Code (VS Code extension or CLI) once you have the repo
open. It gives it full context so it works phase-by-phase instead of trying to do everything
at once.

```
I'm rebuilding a Terraform-based multi-cloud IAM governance project (persona-based RBAC
across Azure/AWS/GCP, JML lifecycle, policy-as-code, audit evidence generation). I have a
rebuild plan in IAM_Project_Rebuild_Plan.md in this repo — read it fully first.

Work through it phase by phase, in order. For each phase:
1. Tell me what you're about to change and why, before making changes.
2. Make the change.
3. Run the relevant validation (terraform validate/plan, conftest test, or the Python
   validator) and show me the output — don't tell me it works without running it.
4. Stop and let me review before moving to the next phase.

Do not skip Phase 0 (security/hygiene). Do not mark anything as "done" in the plan unless
you've actually run it and it passes. If something in the existing code contradicts the
plan, flag it to me rather than silently resolving it.
```

Keep commits small and scoped to one checklist item where possible — that commit history
becomes part of your interview story ("here's how I actually built this incrementally").
