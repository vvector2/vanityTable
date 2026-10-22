# Toaletka

Private app that watches OLX for retro/vintage vanity tables ("toaletka"), filters listings with fuzzy matching, and lets one user accept or reject them.

- Requirements: @docs/mpv.md
- Architecture: @docs/architecture.md

Stack: Python sync job on Lambda (container image, EventBridge), Listings API on FastAPI in an always-on Lightsail container (accepted cost, see `docs/architecture.md`), DynamoDB, Cognito, SSM Parameter Store, React (S3 + CloudFront), Terraform. Region `eu-central-1`.

Repository layout:

- `syncJob/` sync Lambda and the OLX source adapter
- `listingApi/` Listings API (FastAPI), see `docs/llstingApi.md`
- `ui/` React app
- `infra/` Terraform root module with child modules (`infra/README.md`)
- `scripts/` build and deploy scripts: `local/` for your machine (`local/deploy.sh --env dev|prod` is the full deploy, `launch.ps1`, `quick-sync.ps1`), `ci/` for the GitHub Actions deploy, `lib/` shared deploy steps
- `.github/workflows/` CI on pull requests, deploys to `dev` and `prod` (`infra/README.md`)
- `docs/` requirements and architecture

Topic rules live in `.claude/rules/`; repeatable workflows live in `.claude/skills/`.
