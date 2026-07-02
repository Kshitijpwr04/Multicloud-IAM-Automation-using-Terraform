import sys

from policy_input_from_plan import is_break_glass

CASES = [
    # (rtype, address, expected, label)
    (
        "azurerm_role_assignment",
        "module.azure_iam.azurerm_role_assignment.break_glass_owner",
        True,
        "real Azure break_glass grant",
    ),
    (
        "aws_iam_role_policy_attachment",
        'module.aws_iam[0].aws_iam_role_policy_attachment.persona["break_glass::arn:aws:iam::aws:policy/AdministratorAccess"]',
        True,
        "real AWS break_glass grant",
    ),
    (
        "azurerm_role_assignment",
        "module.azure_iam.azurerm_role_assignment.persona_groups[\"security_analyst\"]",
        False,
        "real, unrelated Azure persona grant",
    ),
    (
        "azurerm_role_assignment",
        "module.azure_iam.azurerm_role_assignment.not_break_glass_at_all_but_named_to_slip_through",
        False,
        "forged: resource label contains 'break_glass' as a substring",
    ),
    (
        "azurerm_role_assignment",
        "module.break_glass_totally_unrelated.azurerm_role_assignment.sandbox_reader",
        False,
        "forged: module name contains 'break_glass', unrelated resource",
    ),
    (
        "aws_iam_role_policy_attachment",
        'module.aws_iam[0].aws_iam_role_policy_attachment.sneaky["break_glass::arn:aws:iam::aws:policy/AdministratorAccess"]',
        False,
        "forged: differently-labeled AWS resource reuses the break_glass:: key prefix",
    ),
]

def main():
    failures = []
    for rtype, addr, expected, label in CASES:
        got = is_break_glass(rtype, addr)
        status = "PASS" if got == expected else "FAIL"
        print(f"[{status}] {label}: expected={expected} got={got}")
        if got != expected:
            failures.append(label)

    if failures:
        print(f"\n{len(failures)} of {len(CASES)} cases failed: {failures}")
        sys.exit(1)
    print(f"\nAll {len(CASES)} cases passed.")

if __name__ == "__main__":
    main()
