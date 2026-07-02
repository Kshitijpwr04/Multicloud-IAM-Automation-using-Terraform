import json, sys, subprocess, pathlib

def run(cmd):
    return subprocess.check_output(cmd, text=True)

def is_break_glass(rtype, addr):
    # break_glass is the one persona allowed to hold Owner/AdministratorAccess.
    # Anchored to the *specific* resource construct each module uses for its
    # break_glass persona -- a bare "break_glass" in addr substring check can be
    # spoofed by naming any unrelated resource/module to contain that word (e.g.
    # a resource labeled "not_break_glass_at_all_but_named_to_slip_through", or a
    # module named "break_glass_totally_unrelated"), which would then be exempted
    # from the Owner/AdministratorAccess deny regardless of what it actually grants
    # or to whom. Azure's break_glass role assignment is a single, uniquely
    # labeled resource (azurerm_role_assignment.break_glass_owner, not a for_each);
    # AWS's is specifically the "persona" resource's for_each entry keyed by a
    # "break_glass::<arn>" prefix -- checking both the resource label ("persona")
    # and the key prefix rules out a differently-labeled resource forging the key.
    return (
        rtype == "azurerm_role_assignment"
        and addr.endswith(".azurerm_role_assignment.break_glass_owner")
    ) or (
        rtype == "aws_iam_role_policy_attachment"
        and '.aws_iam_role_policy_attachment.persona["break_glass::' in addr
    )

def main():
    # Accept either a pre-rendered `terraform show -json` output file
    # (path ending in .json) or a raw plan file to render ourselves.
    # Defaults to the raw plan file "tfplan" for backward compatibility
    # with scripts/run_policy_checks.sh, which passes no argument.
    plan_path = sys.argv[1] if len(sys.argv) > 1 else "tfplan"

    if plan_path.endswith(".json"):
        plan_json = pathlib.Path(plan_path).read_text()
    else:
        plan_json = run(["terraform", "show", "-json", plan_path])
    plan = json.loads(plan_json)

    out = []
    rc = plan.get("resource_changes", [])
    for r in rc:
        rtype = r.get("type")
        addr = r.get("address")
        change = r.get("change", {})
        after = change.get("after") or {}

        # Normalize only the IAM-ish resources we care about
        if rtype in ("azurerm_role_assignment", "aws_iam_role_policy_attachment"):
            bg = is_break_glass(rtype, addr)
            out.append({
                "address": addr,
                "resource_type": rtype,
                "values": after,
                "meta": {
                    "allow_owner": bg,
                    "allow_admin": bg
                }
            })

    print(json.dumps(out, indent=2))

if __name__ == "__main__":
    main()