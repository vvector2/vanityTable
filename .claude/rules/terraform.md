---
paths:
  - "infra/**/*.tf"
  - "infra/**/*.tfvars"
---

# Terraform

- One root module deployed as two environments (`dev`, `prod`): settings in `infra/environments/<env>.tfvars`, never in `terraform.tfvars`. Files split by concern (`dynamodb.tf`, `lambda.tf`, `api.tf`, `ui.tf`, `iam.tf`, ...).
- Remote state lives in a manually created S3 bucket with S3 native locking. Never commit state files or `.terraform/`.
- IAM is least privilege: each Lambda gets its own role scoped to the exact table, parameters and log group it uses.
- DynamoDB uses `PAY_PER_REQUEST`.
- Terraform does not build code. It consumes artifacts produced by `scripts/`.
- Run `terraform fmt` and `terraform validate` after changes. Never run `terraform apply` or `destroy` without explicit user approval.
