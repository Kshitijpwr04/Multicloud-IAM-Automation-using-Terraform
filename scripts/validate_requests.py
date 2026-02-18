import sys, pathlib, yaml

REQ_DIR = pathlib.Path("identities/access-requests")
required_top = {"request_type","request_id","requested_by","requested_at","user","justification"}
required_user = {"email","display_name","persona","status"}

def fail(msg):
    print(f"[FAIL] {msg}")
    sys.exit(1)

def main():
    files = list(REQ_DIR.rglob("*.yaml"))
    if not files:
        print("[OK] No request files found.")
        return

    for f in files:
        if f.name.startswith("_TEMPLATE"):
            continue
        data = yaml.safe_load(f.read_text())
        if not isinstance(data, dict):
            fail(f"{f}: must be a YAML object")

        missing = required_top - set(data.keys())
        if missing:
            fail(f"{f}: missing keys: {sorted(missing)}")

        user = data.get("user", {})
        if not isinstance(user, dict):
            fail(f"{f}: user must be a YAML object")

        missing_u = required_user - set(user.keys())
        if missing_u:
            fail(f"{f}: user missing keys: {sorted(missing_u)}")

        # lightweight checks
        if "@" not in user["email"]:
            fail(f"{f}: invalid email")
        if data["request_type"] not in {"joiner","mover","leaver"}:
            fail(f"{f}: invalid request_type")

    print("[OK] Request files validated.")

if __name__ == "__main__":
    try:
        import yaml  # PyYAML
    except ImportError:
        fail("PyYAML not installed. Add it to devcontainer or run: pip install pyyaml")
    main()
