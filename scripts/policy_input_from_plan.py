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
            out.append({
                "address": addr,
                "resource_type": rtype,
                "values": after,
                "meta": {
                    # can be wired later from env, labels, etc.
                    "allow_owner": False,
                    "allow_admin": False
                }
            })

    print(json.dumps(out, indent=2))

if __name__ == "__main__":
    main()