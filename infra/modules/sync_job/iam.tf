data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sync" {
  name               = "${var.name}-sync"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "sync" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.sync.arn}:*"]
  }

  # SecureString with the AWS managed key: its key policy already allows decrypt via SSM.
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sync_client_secret.arn]
  }
}

resource "aws_iam_role_policy" "sync" {
  role   = aws_iam_role.sync.id
  policy = data.aws_iam_policy_document.sync.json
}
