# Quarterly Access Review Report

## Report Metadata

- Review Period: QX 20XX
- Environment: Sandbox / Prod
- Generated On: YYYY-MM-DD
- Reviewer: <Name>
- Approved By: <Security Lead>

---

## 1. Identity Summary

| User | Email | Persona | Status | Last Change |
|------|-------|---------|--------|-------------|
| example | example@company.com | developer | active | 2026-02-20 |

---

## 2. Azure Role Assignments

| Persona | Azure Role | Scope |
|---------|------------|-------|
| developer | Reader | rg-iam-sandbox |

---

## 3. AWS Role Assignments

| Persona | IAM Role | Policies Attached |
|---------|----------|------------------|
| developer | role-dev | ReadOnlyAccess |

---

## 4. GCP Role Assignments

| Persona | GCP Role | Project |
|---------|----------|---------|
| developer | roles/viewer | demo-project |

---

## 5. Privileged Access Review

| User | Privileged Role | Justification | Approved? |
|------|-----------------|---------------|-----------|
| example | Owner | Incident Response | Yes |

---

## 6. Break-Glass Usage (if any)

| Request ID | User | Reason | Approved By | Date |
|------------|------|--------|-------------|------|

---

## 7. Reviewer Sign-Off

I confirm that all access listed above has been reviewed and validated.

Reviewer Signature: ______________________  
Date: ______________________
