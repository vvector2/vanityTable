---
name: deploy
description: Deploy Toaletka to AWS (dev or prod). Builds and pushes the API and sync images, runs a Terraform plan and apply for one environment, then deploys the React app. Use only when the user asks to deploy.
disable-model-invocation: true
---

# Deploy

Usually CI deploys: a push to `master` deploys `dev`, and the "Deploy (manual)" workflow deploys any ref to `dev` or `prod` (`infra/README.md`, section CI/CD). Deploy locally only for an environment's first deployment, or when the user asks.

1. Ask which environment (`dev` or `prod`) if the user did not say. Make sure the working tree is clean, or tell the user what is uncommitted.
2. If `infra/terraform.tfvars` exists, stop: its settings belong in `infra/environments/<env>.tfvars`.
3. The user must be signed in to that environment's AWS account (`aws_account_id` in `infra/environments/<env>.tfvars`); `deploy.sh` stops otherwise. Run `AWS_PROFILE=<profile> ./scripts/local/deploy.sh --env <env> --plan-only` (from WSL or Linux; add `--skip-images` to keep the running images). It builds and pushes the images and writes `infra/tfplan`.
4. Show the user a summary of the plan (`terraform -chdir=infra show tfplan`), especially anything being destroyed or replaced. **Wait for explicit approval**, then run `./scripts/local/deploy.sh --env <env> --apply-plan`. It applies the plan, builds the UI with `VITE_API_URL=/api` and the Cognito settings from Terraform, uploads it, invalidates CloudFront and calls `/api/health`.
5. Report the smoke test result and the URLs it prints.
