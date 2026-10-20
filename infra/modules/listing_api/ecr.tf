resource "aws_ecr_repository" "api" {
  name                 = "${var.name}-listings-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# Lets the Lightsail container service pull from this private repository.
data "aws_iam_policy_document" "lightsail_pull" {
  statement {
    sid     = "AllowLightsailPull"
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    principals {
      type        = "AWS"
      identifiers = [aws_lightsail_container_service.api.private_registry_access[0].ecr_image_puller_role[0].principal_arn]
    }
  }
}

resource "aws_ecr_repository_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy     = data.aws_iam_policy_document.lightsail_pull.json
}
