# GitHub Actions access (.github/workflows/deploy.yml): OIDC provider plus two roles per
# environment. The plan role reads everything and pushes images; the deploy role applies.
# See infra/README.md, section CI/CD.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
