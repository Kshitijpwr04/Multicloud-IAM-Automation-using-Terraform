import json, sys, subprocess, pathlib

def run(cmd):
    return subprocess.check_output(cmd, text=True)

def main():
    # Expect caller to create plan file: tfplan
    plan_json = run(["terraform", "show", "-json", "tfplan"])
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