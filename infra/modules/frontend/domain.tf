# Only when custom_domain is set: certificate in us-east-1 (CloudFront requirement),
# DNS validation and alias records in the existing hosted zone.

data "aws_route53_zone" "main" {
  count = local.custom_domain ? 1 : 0
  name  = var.custom_domain.hosted_zone_name
}

resource "aws_acm_certificate" "ui" {
  count             = local.custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.custom_domain.name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.custom_domain ? {
    for option in aws_acm_certificate.ui[0].domain_validation_options : option.domain_name => option
  } : {}

  zone_id         = data.aws_route53_zone.main[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "ui" {
  count                   = local.custom_domain ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.ui[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_route53_record" "ui" {
  for_each = local.custom_domain ? toset(["A", "AAAA"]) : toset([])

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.custom_domain.name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.ui.domain_name
    zone_id                = aws_cloudfront_distribution.ui.hosted_zone_id
    evaluate_target_health = false
  }
}
