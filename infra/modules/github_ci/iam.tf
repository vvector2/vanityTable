data "aws_caller_identity" "current" {}

locals {
  account    = data.aws_caller_identity.current.account_id
  state_arn  = "arn:aws:s3:::${var.state_bucket}/${var.state_key}"
  ecr_repos  = "arn:aws:ecr:*:${local.account}:repository/${var.name}-*"
  read_only  = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  iam_prefix = "arn:aws:iam::${local.account}"
}

# Plan role: terraform plan, plus pushing the images the plan points at.

resource "aws_iam_role" "plan" {
  name               = "${var.name}-github-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = local.read_only
}

data "aws_iam_policy_document" "plan" {
  # S3 native locking writes and deletes a lock object next to the state.
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}.tflock"]
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [local.ecr_repos]
  }
}

resource "aws_iam_role_policy" "plan" {
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# Deploy role: terraform apply of the whole stack, the UI upload and the invalidation.
# It manages this module too, so it can widen its own policy; the gate is the GitHub
# environment's required reviewer, not this policy.

resource "aws_iam_role" "deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

resource "aws_iam_role_policy_attachment" "deploy_read_only" {
  role       = aws_iam_role.deploy.name
  policy_arn = local.read_only
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_arn, "${local.state_arn}.tflock"]
  }

  # Resources named after var.name.
  statement {
    actions = ["dynamodb:*", "lambda:*", "logs:*", "events:*", "ecr:*", "ssm:*", "s3:*"]
    resources = [
      "arn:aws:dynamodb:*:${local.account}:table/${var.name}-*",
      "arn:aws:lambda:*:${local.account}:function:${var.name}-*",
      "arn:aws:logs:*:${local.account}:log-group:/aws/lambda/${var.name}-*",
      "arn:aws:events:*:${local.account}:rule/${var.name}-*",
      local.ecr_repos,
      "arn:aws:ssm:*:${local.account}:parameter/${var.name}/*",
      "arn:aws:s3:::${var.name}-*",
    ]
  }

  statement {
    actions = ["iam:*"]
    resources = concat(
      [
        "${local.iam_prefix}:role/${var.name}-*",
        "${local.iam_prefix}:user/${var.name}-*",
      ],
      var.create_oidc_provider ? [local.oidc_provider_arn] : [],
    )
  }

  # IDs are generated (user pools, distributions, certificates, zones) or the service
  # has no resource-level permissions (Lightsail), so these cannot be scoped by name.
  statement {
    actions = [
      "cognito-idp:*",
      "cloudfront:*",
      "acm:*",
      "route53:*",
      "lightsail:*",
      "ecr:GetAuthorizationToken",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
