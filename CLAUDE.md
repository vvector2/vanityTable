# Toaletka

Private app that watches OLX for retro/vintage vanity tables ("toaletka"), filters listings with fuzzy matching, and lets one user accept or reject them.

- Requirements: @docs/mpv.md
- Architecture: @docs/architecture.md

Stack: Python Lambdas, DynamoDB, EventBridge, SSM Parameter Store, React (S3 + CloudFront), Terraform. Region `eu-central-1` (proposed).

Repository layout (planned):

- `backend/` Python Lambdas (`sync`, `api`) and the OLX source adapter
- `ui/` React app
- `infra/` Terraform root module
- `scripts/` build and deploy scripts
- `docs/` requirements and architecture

Topic rules live in `.claude/rules/`; repeatable workflows live in `.claude/skills/`.
