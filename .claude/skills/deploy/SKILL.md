---
name: deploy
description: Deploy Toaletka to AWS. Builds and pushes the API and sync images, runs a Terraform plan and apply, then deploys the React app with scripts/deploy-ui.ps1. Use only when the user asks to deploy.
disable-model-invocation: true
---

# Deploy

1. Make sure the working tree is clean, or tell the user what is uncommitted.
2. Build and push the images: `./scripts/build-api-image.ps1 -Push` and `./scripts/build-sync-image.ps1 -Push`. Put the printed tags into `api_image_tag` and `sync_image_tag` in `infra/terraform.tfvars` (untracked; see `infra/README.md`). Skip an image whose code did not change and keep its current tag.
3. In `infra/`, run `terraform fmt -check`, `terraform validate` and `terraform plan -out=tfplan`.
4. Show the user a summary of the plan, especially anything being destroyed or replaced. **Wait for explicit approval**, then run `terraform apply tfplan`.
5. Deploy the UI with `./scripts/deploy-ui.ps1`. It builds with `VITE_API_URL=/api` and the API key from Terraform, uploads to the UI bucket and invalidates CloudFront. Do not run `npm run build` by hand: without those variables the build calls `http://localhost:8000`.
6. Smoke test: open the UI URL (`terraform output ui_url`) and call `GET <ui_url>/api/health`. Report the results and the URLs.
