## Access Request Type
- [ ] Joiner
- [ ] Mover
- [ ] Leaver

## Request File(s)
Link the YAML file(s) changed under `identities/access-requests/`.

## Justification (business + security)
Explain why access is needed / why change is required.

## Risk Notes
- Does this touch privileged roles (Owner/Admin/Break-glass)?
- Any compliance constraints (SOX/HIPAA/PCI)?

## Validation
- [ ] `python scripts/validate_requests.py` passes locally
- [ ] GitHub Actions checks pass
