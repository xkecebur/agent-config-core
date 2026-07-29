---
name: iac-review
description: Infrastructure as Code review — Terraform state security, version pinning, drift, and the cloud misconfigurations that most often turn into incidents (open security groups, public storage, IAM wildcards, unencrypted volumes). Use when writing or reviewing .tf/.tfvars files, discussing Terraform state and backends, or auditing cloud configuration before an apply.
globs:
  - "**/*.tf"
  - "**/*.tfvars"
alwaysApply: false
---

# Infrastructure as Code — Review

Dockerfile and Kubernetes manifest hardening lives in `security-audit`.

## Terraform state — easy to overlook, expensive to get wrong

- [ ] **State stores secrets in plaintext** — RDS passwords, private keys, tokens are all
      there verbatim. State is not a secret store, and it is not safe to share casually
- [ ] Remote backend with encryption at rest (`encrypt = true` for S3) and versioning enabled
- [ ] State locking enabled (DynamoDB for S3, or a backend that supports it) — without it,
      concurrent applies corrupt state
- [ ] State bucket is **not public**, access restricted and logged
- [ ] State never committed to git (`*.tfstate*` in `.gitignore`)

## Pinning — reproducibility and supply chain

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

module "vpc" {
  source = "git::https://github.com/org/modules.git//vpc?ref=v1.4.2"  # tag or SHA, not a branch
}
```

- [ ] Providers pinned (at minimum `~>`), `.terraform.lock.hcl` committed
- [ ] External modules pinned to a tag or commit, **never `main`** — a third-party module
      that can change under you is code execution at plan time

## Misconfigurations that most often become incidents

| Finding | Severity | Pattern |
|---|---|---|
| Security group ingress `0.0.0.0/0` to an admin port (22/3389/5432/6379/27017) | **Critical** | `cidr_blocks = ["0.0.0.0/0"]` |
| Public storage (S3 ACL/policy, GCS allUsers, public Blob) | **Critical** | also check `block_public_access` |
| IAM policy with `Action: "*"` or `Resource: "*"` | **High** | wildcards enable privilege escalation |
| Volume or database without encryption at rest | **High** | `storage_encrypted`, `encrypted` |
| `publicly_accessible = true` on a database instance | **Critical** | RDS directly on the internet |
| Secrets hardcoded in `.tf` / `.tfvars` | **Critical** | use a secret manager, mark `sensitive = true` |
| Audit logging disabled (CloudTrail, VPC flow logs) | **Medium** | blocks detection and forensics |
| No `prevent_destroy` on stateful resources | **Medium** | `lifecycle { prevent_destroy = true }` |

## Plan and apply discipline

- **Always read `terraform plan` before applying.** Pay attention to `destroy` and
  replacement (`-/+`) lines
- A replaced database or volume means data loss. Check which attribute
  `forces replacement`
- `-auto-approve` belongs only in a pipeline with a reviewed plan, never in an
  interactive production session
- A clean plan is not proof of no drift — manual console changes are not detected for
  every attribute

## Tooling

Run these before manual review so human attention goes to what tools cannot catch:

```bash
terraform fmt -check -recursive
terraform validate
tflint
tfsec .          # or: trivy config .
checkov -d .
```

## Quick checklist

- [ ] `terraform plan` reviewed; no unintended destroy or replace
- [ ] No secrets in code or default variable values
- [ ] Providers and modules pinned
- [ ] Backend secure: encrypted, locked, versioned, private
- [ ] No `0.0.0.0/0` to sensitive ports
- [ ] Encryption at rest enabled for storage and databases
- [ ] Stateful resources protected against destroy
