data "archive_file" "zip_payload" {
  type        = "zip"
  source_file = var.function_code_src_path
  output_path = var.function_code_output_path
}

# Create a DDB
resource "aws_dynamodb_table" "ddb" {
  name         = format("%s-table", var.project_name)
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = format("%s-iam-for-lambda", var.project_name)
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
  }
    EOF
}

resource "aws_iam_policy" "micro-service-function-policy" {
  name        = format("%s-micro-service-function-policy", var.project_name)
  description = format("A policy for letting lambda functions interact with the dynamodb table for project %s.", var.project_name)

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:DeleteItem",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:Scan",
                "dynamodb:UpdateItem"
            ],
            "Resource": "${aws_dynamodb_table.ddb.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "table-policy-attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.micro-service-function-policy.arn
}

resource "aws_iam_role_policy_attachment" "basic-executor-attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "function" {

  function_name = format("%s-function", var.project_name)
  role          = aws_iam_role.iam_for_lambda.arn

  handler = "${var.handler_file_name}.handler"
  runtime = "nodejs16.x"

  filename         = data.archive_file.zip_payload.output_path
  source_code_hash = filebase64sha256(data.archive_file.zip_payload.output_path)
}

resource "aws_apigatewayv2_api" "gw_api" {
  name                         = format("%s-api", var.project_name)
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = true

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type"]
    allow_methods     = ["*"]
    allow_origins     = [format("https://%s", var.domain_name)]
    expose_headers    = []
    max_age           = 100
  }
}

resource "aws_apigatewayv2_stage" "api_gw_stage" {

  api_id      = aws_apigatewayv2_api.gw_api.id
  name        = "$default"
  auto_deploy = true

}

resource "aws_apigatewayv2_route" "api_routes" {
  for_each = toset(var.routes)
  api_id   = aws_apigatewayv2_api.gw_api.id

  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.gw_api_integration.id}"
}

resource "aws_apigatewayv2_integration" "gw_api_integration" {
  api_id           = aws_apigatewayv2_api.gw_api.id
  integration_type = "AWS_PROXY"

  payload_format_version = "2.0"

  description        = format("API integration for %s routes", var.project_name)
  integration_method = "POST"
  integration_uri    = aws_lambda_function.function.invoke_arn
}

resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "apigateway.amazonaws.com"
}


resource "aws_route53domains_registered_domain" "domain" {
  domain_name = var.domain_name

  name_server {
    name = aws_route53_zone.hosted_zone.name_servers[0]
  }

  name_server {
    name = aws_route53_zone.hosted_zone.name_servers[1]
  }

   name_server {
    name = aws_route53_zone.hosted_zone.name_servers[2]
  }

   name_server {
    name = aws_route53_zone.hosted_zone.name_servers[3]
  }
}

resource "aws_route53_zone" "hosted_zone" {
  comment = format("Created for %s", var.project_name)
  name    = var.domain_name
}

resource "aws_route53_record" "NS_record" {
  allow_overwrite = true
  name            = var.domain_name
  ttl             = 172800
  type            = "NS"
  zone_id         = aws_route53_zone.hosted_zone.zone_id

  records = [
    aws_route53_zone.hosted_zone.name_servers[0],
    aws_route53_zone.hosted_zone.name_servers[1],
    aws_route53_zone.hosted_zone.name_servers[2],
    aws_route53_zone.hosted_zone.name_servers[3],
  ]
}

resource "aws_route53_record" "api_gw_record" {
  name    = var.api_domain_name
  type    = "A"
  zone_id = aws_route53_zone.hosted_zone.zone_id
  alias {
    evaluate_target_health = true
    name                   = aws_apigatewayv2_domain_name.api_gateway_domain_name.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api_gateway_domain_name.domain_name_configuration[0].hosted_zone_id
  }
}

# resource "aws_route53_record" "www" {
#   zone_id = aws_route53_zone.hosted_zone.zone_id
#   name    = var.www_domain_name
#   type    = "A"
#   ttl     = 300
#   records = []
# }

resource "aws_acm_certificate" "api_domain_certificate" {
  domain_name       = var.api_domain_name
  validation_method = "DNS"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "domain_certificate" {
  domain_name = var.domain_name
  provider    = aws.virginia
  subject_alternative_names = [
    var.www_domain_name
  ]
  validation_method = "DNS"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "domain_cname_records" {
  for_each = {
    for dvo in aws_acm_certificate.domain_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.hosted_zone.zone_id
}
resource "aws_route53_record" "api_cname_records" {
  for_each = {
    for dvo in aws_acm_certificate.api_domain_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.hosted_zone.zone_id
}

resource "aws_acm_certificate_validation" "domain_certificate_validation" {
  certificate_arn         = aws_acm_certificate.domain_certificate.arn
  provider = aws.virginia
  validation_record_fqdns = [for record in aws_route53_record.domain_cname_records : record.fqdn]

}

resource "aws_acm_certificate_validation" "api_certificate_validation" {
  certificate_arn         = aws_acm_certificate.api_domain_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cname_records : record.fqdn]
}

resource "aws_apigatewayv2_domain_name" "api_gateway_domain_name" {
  domain_name = var.api_domain_name
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api_certificate_validation.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api_gw_mapping" {
  api_id      = aws_apigatewayv2_api.gw_api.id
  domain_name = aws_apigatewayv2_domain_name.api_gateway_domain_name.id
  stage       = aws_apigatewayv2_stage.api_gw_stage.id
}


data "external" "frontend_build" {
  program = ["bash", "-c", <<EOT
    # Relative to working_dir
    # (npm ci && npm run build) >&2 &&
     echo "{\"dest\": \"dist\"}"
    EOT
  ]
  working_dir = format("${path.module}/%s", var.frontend_src_path)
}

resource "aws_s3_bucket_object" "build_uploader" {
  for_each = fileset("${data.external.frontend_build.working_dir}/${data.external.frontend_build.result.dest}/", "**")
  bucket   = aws_s3_bucket.root_bucket.bucket
  key      = each.value
  source   = "aws_s3_bucket/${each.value}"
  etag     = filemd5("aws_s3_bucket/${each.value}")
}

resource "aws_s3_bucket" "root_bucket" {
  bucket        = var.domain_name
  force_destroy = false
}

resource "aws_s3_bucket_website_configuration" "root_bucket_website_configuration" {
  bucket = aws_s3_bucket.root_bucket.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "root_bucket_public_access_block" {
  bucket = aws_s3_bucket.root_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_get_access_s3_bucket_policy" {
  bucket = aws_s3_bucket.root_bucket.id
  policy = data.aws_iam_policy_document.allow_public_get_access.json
}

data "aws_iam_policy_document" "allow_public_get_access" {
  statement {
    sid = "PublicReadGetObject"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.root_bucket.arn,
      "${aws_s3_bucket.root_bucket.arn}/*",
    ]
  }
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  provider = aws.virginia
  aliases = [
    var.domain_name,
  ]
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  retain_on_delete    = true
  wait_for_deployment = true

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 0
  }

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
    ]
    cache_policy_id = data.aws_cloudfront_cache_policy.root_bucket_cloudfront_cache_policy.id
    cached_methods = [
      "GET",
      "HEAD",
    ]
    compress               = true
    default_ttl            = 0
    max_ttl                = 0
    min_ttl                = 0
    smooth_streaming       = false
    target_origin_id       = aws_s3_bucket.root_bucket.bucket_regional_domain_name
    trusted_key_groups     = []
    trusted_signers        = []
    viewer_protocol_policy = "redirect-to-https"
  }

  origin {
    connection_attempts = 3
    connection_timeout  = 10
    domain_name         = aws_s3_bucket.root_bucket.bucket_regional_domain_name
    origin_id           = aws_s3_bucket.root_bucket.bucket_regional_domain_name
  }

  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate_validation.domain_certificate_validation.certificate_arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}


data "aws_cloudfront_cache_policy" "root_bucket_cloudfront_cache_policy" {
  name = "Managed-CachingDisabled"
}

resource "aws_route53_record" "cloudfront_record" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.hosted_zone.zone_id
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront_distribution.hosted_zone_id
  }
}
