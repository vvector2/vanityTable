---
name: deploy
description: Deploy Toaletka to AWS. Packages the Lambdas, runs a Terraform plan and apply, builds the React app, uploads it to S3 and invalidates CloudFront. Use only when the user asks to deploy.
disable-model-invocation: true
---

# Deploy

1. Make sure the working tree is clean, or tell the user what is uncommitted.
2. Run the `package-lambda` skill.
3. In `infra/`, run `terraform fmt -check`, `terraform validate` and `terraform plan -out=tfplan`.
4. Show the user a summary of the plan, especially anything being destroyed or replaced. **Wait for explicit approval**, then run `terraform apply tfplan`.
5. Build the UI: `npm ci && npm run build` in `ui/`.
6. Read the bucket name and distribution ID from `terraform output`, then:
   ```
   aws s3 sync ui/dist s3://<bucket> --delete
   aws cloudfront create-invalidation --distribution-id <id> --paths "/*"
   ```
7. Smoke test: call `GET /sync-status` and open the UI URL. Report the results and the URLs.
