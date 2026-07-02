import json, sys, subprocess, pathlib

def run(cmd):
    return subprocess.check_output(cmd, text=True)

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
            # break_glass is the one persona allowed to hold Owner/AdministratorAccess --
            # every module names its break_glass resources with "break_glass" in the
            # Terraform address (module.azure_iam...break_glass_owner,
            # aws_iam_role_policy_attachment.persona["break_glass::..."]), so that's a
            # reliable signal without needing a separate allowlist file.
            is_break_glass = "break_glass" in addr
            out.append({
                "address": addr,
                "resource_type": rtype,
                "values": after,
                "meta": {
                    "allow_owner": is_break_glass,
                    "allow_admin": is_break_glass
                }
            })

    print(json.dumps(out, indent=2))

if __name__ == "__main__":
    main()