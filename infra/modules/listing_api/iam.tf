# Lightsail containers have no IAM role, so the API signs DynamoDB calls with this user's keys.
resource "aws_iam_user" "api" {
  name = "${var.name}-listings-api"
}

data "aws_iam_policy_document" "api" {
  statement {
    actions = [
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [var.listings_table_arn, "${var.listings_table_arn}/index/*"]
  }
}

resource "aws_iam_user_policy" "api" {
  user   = aws_iam_user.api.name
  policy = data.aws_iam_policy_document.api.json
}

# The secret ends up in the Terraform state, which is why the state bucket must stay private.
resource "aws_iam_access_key" "api" {
  user = aws_iam_user.api.name
}
