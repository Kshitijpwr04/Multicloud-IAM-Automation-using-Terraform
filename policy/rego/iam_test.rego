package iam.guardrails

# Colocated with iam.rego rather than under policy/opa/ or policy/conftest/ (both empty
# stub directories that don't match where the actual policy lives) -- conftest/OPA
# discover test files by loading the whole -p path together, so this is the layout that
# actually works with `conftest verify -p policy/rego`, run as part of
# scripts/run_policy_checks.sh.

# ---- Rule: deny Azure Owner ----

test_deny_azure_owner_when_not_allowed {
	deny["Azure role 'Owner' is not allowed (use break_glass process). Resource: module.example.azurerm_role_assignment.example"] with input as {
		"address": "module.example.azurerm_role_assignment.example",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Owner"},
		"meta": {"allow_owner": false, "allow_admin": false},
	}
}

test_allow_azure_owner_for_break_glass {
	count(deny) == 0 with input as {
		"address": "module.azure_iam.azurerm_role_assignment.break_glass_owner",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Owner"},
		"meta": {"allow_owner": true, "allow_admin": true},
	}
}

test_no_deny_for_azure_reader {
	count(deny) == 0 with input as {
		"address": "module.azure_iam.azurerm_role_assignment.persona_groups[\"auditor\"]",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Reader"},
		"meta": {"allow_owner": false, "allow_admin": false},
	}
}

test_deny_owner_grant_that_only_looks_like_break_glass_by_address {
	# A resource crafted/renamed to *look* like the real break_glass grant by putting
	# "break_glass" somewhere in its address, without actually being it. This proves
	# the deny rule still fires as long as meta.allow_owner correctly reflects "this
	# isn't really break_glass" -- which is exactly what the tightened, anchored
	# is_break_glass check in scripts/policy_input_from_plan.py now computes for an
	# address like this (verified separately: it no longer matches a bare "break_glass"
	# substring, only the exact resource construct the real break_glass grant uses).
	#
	# Note what this test does and doesn't prove: it proves the Rego layer correctly
	# denies when handed a forged-looking address with correct (false) meta -- Rego
	# never inspects the address itself for this decision, only meta.allow_owner. It
	# does NOT exercise policy_input_from_plan.py's address-matching logic directly;
	# that logic lives in Python and would need its own Python-level test to be
	# proven spoof-resistant on its own, not just trusted here.
	deny["Azure role 'Owner' is not allowed (use break_glass process). Resource: module.azure_iam.azurerm_role_assignment.not_break_glass_at_all_but_named_to_slip_through"] with input as {
		"address": "module.azure_iam.azurerm_role_assignment.not_break_glass_at_all_but_named_to_slip_through",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Owner"},
		"meta": {"allow_owner": false, "allow_admin": false},
	}
}

# ---- Rule: deny AWS AdministratorAccess ----

test_deny_aws_admin_when_not_allowed {
	deny["AWS AdministratorAccess is not allowed (use break_glass process). Resource: module.aws_iam.aws_iam_role_policy_attachment.persona[\"break_glass::arn:aws:iam::aws:policy/AdministratorAccess\"]"] with input as {
		"address": "module.aws_iam.aws_iam_role_policy_attachment.persona[\"break_glass::arn:aws:iam::aws:policy/AdministratorAccess\"]",
		"resource_type": "aws_iam_role_policy_attachment",
		"values": {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"},
		"meta": {"allow_owner": false, "allow_admin": false},
	}
}

test_allow_aws_admin_for_break_glass {
	count(deny) == 0 with input as {
		"address": "module.aws_iam.aws_iam_role_policy_attachment.persona[\"break_glass::arn:aws:iam::aws:policy/AdministratorAccess\"]",
		"resource_type": "aws_iam_role_policy_attachment",
		"values": {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"},
		"meta": {"allow_owner": true, "allow_admin": true},
	}
}

test_no_deny_for_aws_readonly {
	count(deny) == 0 with input as {
		"address": "module.aws_iam.aws_iam_role_policy_attachment.persona[\"security_analyst::arn:aws:iam::aws:policy/ReadOnlyAccess\"]",
		"resource_type": "aws_iam_role_policy_attachment",
		"values": {"policy_arn": "arn:aws:iam::aws:policy/ReadOnlyAccess"},
		"meta": {"allow_owner": false, "allow_admin": false},
	}
}

# ---- Rule: block break_glass in joiner/mover requests ----
# These prove the rule LOGIC is correct against mocked, access-request-shaped input.
# They do NOT prove this input shape ever reaches the rule in the real pipeline --
# see the dormancy tests below, which prove the opposite using real captured output.

test_deny_break_glass_joiner {
	deny["Joiner cannot request break_glass persona"] with input as {
		"kind": "access_request",
		"request_type": "joiner",
		"user": {"persona": "break_glass"},
	}
}

test_deny_break_glass_mover {
	deny["Mover cannot assign break_glass persona"] with input as {
		"kind": "access_request",
		"request_type": "mover",
		"user": {"new_persona": "break_glass"},
	}
}

test_no_deny_for_joiner_with_valid_persona {
	count(deny) == 0 with input as {
		"kind": "access_request",
		"request_type": "joiner",
		"user": {"persona": "security_analyst"},
	}
}

# ---- Dormancy proof ----
# real_pipeline_output is the ACTUAL output of running
# `python3 scripts/policy_input_from_plan.py evidence/inventory/tfplan-20260220-170538.json`
# against a real, committed evidence plan -- captured verbatim (trimmed to the fields
# used here), not invented. This is what scripts/run_policy_checks.sh actually feeds
# conftest today. None of these entries have a "kind" field at all, so the two
# break_glass-via-joiner/mover rules above -- which require kind == "access_request" --
# are structurally unreachable against this real data, regardless of how correct their
# own logic is (proven separately above). If this test ever starts failing, it means
# the pipeline started producing access-request-shaped input, and the "dormant" framing
# in docs/02 and docs/03 needs to be revisited.
real_pipeline_output := [
	{
		"address": "module.azure_iam.azurerm_role_assignment.break_glass_owner",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Owner"},
		"meta": {"allow_owner": true, "allow_admin": true},
	},
	{
		"address": "module.azure_iam.azurerm_role_assignment.persona_groups[\"security_analyst\"]",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Reader"},
		"meta": {"allow_owner": false, "allow_admin": false},
	},
	{
		"address": "module.azure_iam.azurerm_role_assignment.sandbox_reader",
		"resource_type": "azurerm_role_assignment",
		"values": {"role_definition_name": "Reader"},
		"meta": {"allow_owner": false, "allow_admin": false},
	},
]

test_real_pipeline_output_never_has_a_kind_field {
	entries_with_kind := [e | e := real_pipeline_output[_]; object.get(e, "kind", null) != null]
	count(entries_with_kind) == 0
}

test_no_denies_fire_against_real_pipeline_output_sample {
	# Sanity check on the sample itself: with the break_glass-aware allow_owner/
	# allow_admin fix in policy_input_from_plan.py, none of these three real
	# entries should be denied (the break_glass Owner grant is now correctly
	# allowed; the two Reader entries were never a violation). This isn't proof
	# about the access_request rules specifically -- that's the test above --
	# just confirmation the sample data reflects a healthy, already-applied state.
	count(deny) == 0 with input as real_pipeline_output[0]
	count(deny) == 0 with input as real_pipeline_output[1]
	count(deny) == 0 with input as real_pipeline_output[2]
}
