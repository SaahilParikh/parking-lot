data "external" "frontend_build" {
	program = ["bash", "-c", <<EOT
    # Relative to working_dir
    (npm ci && npm run build) >&2 && echo "{\"dest\": \"dist\"}"
    EOT
    ]
	working_dir = "${path.module}/../../src/frontend/parking-lot"
}

resource "aws_s3_bucket_object" "build_uploader" {
  for_each = fileset("${data.external.frontend_build.working_dir}/${data.external.frontend_build.result.dest}/", "**")
  bucket = aws_s3_bucket.root_bucket.bucket
  key = each.value
  source = "aws_s3_bucket/${each.value}"
  etag = filemd5("aws_s3_bucket/${each.value}")
}

resource "aws_s3_bucket" "root_bucket" {
    bucket                      = var.domain_name
    force_destroy               = false
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

resource "aws_acm_certificate" "saahil_io_certificate" {
  domain_name = var.domain_name
  provider = aws.virginia
  subject_alternative_names = [
    var.domain_name,
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
resource "aws_cloudfront_distribution" "cloudfront_distribution" {
    aliases                        = [
        var.domain_name,
    ]
    default_root_object            = "index.html"
    enabled                        = true
    http_version                   = "http2and3"
    is_ipv6_enabled                = true
    retain_on_delete               = true
    wait_for_deployment            = true

    custom_error_response {
        error_caching_min_ttl = 10
        error_code            = 404
        response_code         = 0
    }

    default_cache_behavior {
        allowed_methods        = [
            "GET",
            "HEAD",
        ]
        cache_policy_id        = aws_cloudfront_cache_policy.root_bucket_cloudfront_cache_policy.id
        cached_methods         = [
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
        acm_certificate_arn            = aws_acm_certificate.saahil_io_certificate.arn
        cloudfront_default_certificate = false
        minimum_protocol_version       = "TLSv1.2_2021"
        ssl_support_method             = "sni-only"
    }
}


resource "aws_cloudfront_cache_policy" "root_bucket_cloudfront_cache_policy" {
    comment     = "Default policy when CF compression is enabled"
    default_ttl = 86400
    max_ttl     = 31536000
    min_ttl     = 1
    name        = "Managed-CachingDisabled"

    parameters_in_cache_key_and_forwarded_to_origin {
        enable_accept_encoding_brotli = true
        enable_accept_encoding_gzip   = true

        cookies_config {
            cookie_behavior = "none"
        }

        headers_config {
            header_behavior = "none"
        }

        query_strings_config {
            query_string_behavior = "none"
        }
    }
}

resource "aws_route53_zone" "saahil_io_hosted_zone" {
  comment = "HostedZone created by Route53 Registrar for parking-lot"
  name    = var.domain_name
  tags         = {
      "Type" = "Both"
  }
  tags_all     = {
      "Project" = "parking-lot"
      "Type"    = "Both"
  }
}

resource "aws_route53_record" "saahil_io_cloudfront_record" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.saahil_io_hosted_zone.zone_id
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront_distribution.hosted_zone_id
  }
}