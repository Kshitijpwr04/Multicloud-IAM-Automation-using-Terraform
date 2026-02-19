import sys, pathlib, yaml

REQ_DIR = pathlib.Path("identities/access-requests")
USERS_FILE = pathlib.Path("identities/users.yaml")
PERSONAS_FILE = pathlib.Path("identities/personas.yaml")

def fail(msg):
    print(f"[FAIL] {msg}")
    sys.exit(1)

def load_yaml(path: pathlib.Path):
    if not path.exists():
        fail(f"Missing required file: {path}")
    return yaml.safe_load(path.read_text())

def main():
    personas = load_yaml(PERSONAS_FILE)
    users = load_yaml(USERS_FILE)

    persona_keys = set()
    # support either: { personas: [...] } or { personas: {key:...}} styles
    if isinstance(personas, dict) and "personas" in personas:
        if isinstance(personas["personas"], list):
            for p in personas["personas"]:
                k = p.get("key") or p.get("name") or p.get("persona")
                if k: persona_keys.add(str(k))
        elif isinstance(personas["personas"], dict):
            persona_keys |= set(personas["personas"].keys())

    if not persona_keys:
        # fallback: infer from terraform mapping will happen later; but for now require at least 1
        fail("Could not detect persona keys from identities/personas.yaml")

    users_list = []
    if isinstance(users, dict) and "users" in users and isinstance(users["users"], list):
        users_list = users["users"]
    users_by_email = {str(u.get("email","")).lower(): u for u in users_list if u.get("email")}

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

        rtype = data.get("request_type")
        if rtype not in {"joiner","mover","leaver"}:
            fail(f"{f}: invalid request_type: {rtype}")

        for k in ["request_type","request_id","requested_by","requested_at","user","justification"]:
            if k not in data:
                fail(f"{f}: missing key: {k}")

        user = data.get("user")
        if not isinstance(user, dict):
            fail(f"{f}: user must be an object")

        # Common email check
        email = str(user.get("email","")).lower()
        if "@" not in email:
            fail(f"{f}: invalid or missing user.email")

        if rtype == "joiner":
            for k in ["display_name","persona","status"]:
                if k not in user:
                    fail(f"{f}: joiner missing user.{k}")
            persona = str(user["persona"])
            if persona not in persona_keys:
                fail(f"{f}: unknown persona '{persona}'. Valid: {sorted(persona_keys)}")
            if email in users_by_email:
                fail(f"{f}: joiner user already exists in users.yaml: {email}")

        if rtype == "mover":
            if "new_persona" not in user:
                fail(f"{f}: mover missing user.new_persona")
            new_persona = str(user["new_persona"])
            if new_persona not in persona_keys:
                fail(f"{f}: unknown new_persona '{new_persona}'. Valid: {sorted(persona_keys)}")
            if email not in users_by_email:
                fail(f"{f}: mover user not found in users.yaml: {email}")

            # v1 guardrail: break_glass cannot be assigned via mover request
            if new_persona == "break_glass":
                fail(f"{f}: mover cannot assign break_glass. Use a dedicated emergency process.")

        if rtype == "leaver":
            if email not in users_by_email:
                fail(f"{f}: leaver user not found in users.yaml: {email}")

    print("[OK] Request files validated (joiner/mover/leaver).")

if __name__ == "__main__":
    try:
        import yaml  # PyYAML
    except ImportError:
        fail("PyYAML not installed. Run: pip install pyyaml")
    main()
