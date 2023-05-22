locals {
  module_id = substr(sha256(var.hostname), 0, 6)
}

provider "aws" {
  // Lambda@Edge and cert needs to be used in the "us-east-1" region
  alias  = "us-east-1"
  region = "us-east-1"
}

// Cert & DNS

resource "aws_acm_certificate" "branch" {
  provider          = aws.us-east-1
  domain_name       = "branch.${var.hostname}"
  validation_method = "DNS"
  subject_alternative_names = [
    "*.branch.${var.hostname}"
  ]

  tags = {
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }
}

// DNS based certificate validation
resource "aws_route53_record" "branch_validation" {
  for_each = {
    for dvo in aws_acm_certificate.branch.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  zone_id         = var.hosted_zone_id
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_route53_record" "branch_cloudfront" {
  for_each = toset(["branch", "*.branch"])
  zone_id  = var.hosted_zone_id
  name     = "${each.value}.${var.hostname}."
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

// Lambda

locals {
  lambda_function_name = "handler"
  viewer_request_name  = "viewer_request"
  viewer_request_file  = "${local.viewer_request_name}.js"
  origin_response_name = "origin_response"
  origin_response_file = "${local.origin_response_name}.js"
}

data "archive_file" "viewer_request" {
  type        = "zip"
  output_path = "${path.module}/${local.viewer_request_file}.zip"
  source_content = templatefile(
    "${path.module}/${local.viewer_request_file}",
    { "hostname"       = var.hostname,
      "default_object" = var.default_object,
    }
  )
  source_content_filename = local.viewer_request_file
}

data "archive_file" "origin_response" {
  type        = "zip"
  output_path = "${path.module}/${local.origin_response_file}.zip"
  source_file = "${path.module}/${local.origin_response_file}"
}

resource "aws_lambda_function" "viewer_request" {
  provider = aws.us-east-1

  function_name    = "cloudfront-subdomains-viewer-request-${local.module_id}"
  filename         = data.archive_file.viewer_request.output_path
  source_code_hash = data.archive_file.viewer_request.output_base64sha256

  publish = true
  handler = "${local.viewer_request_name}.${local.lambda_function_name}"
  runtime = "nodejs16.x"
  role    = aws_iam_role.lambda_edge_execution.arn

  tags = {
    Name              = "cloudfront-subdomains-viewer-request-${local.module_id}"
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }
}

resource "aws_lambda_function" "origin_response" {
  provider = aws.us-east-1

  function_name    = "cloudfront-subdomains-origin-response-${local.module_id}"
  filename         = data.archive_file.origin_response.output_path
  source_code_hash = data.archive_file.origin_response.output_base64sha256

  publish = true
  handler = "${local.origin_response_name}.${local.lambda_function_name}"
  runtime = "nodejs16.x"
  role    = aws_iam_role.lambda_edge_execution.arn

  tags = {
    Name              = "cloudfront-subdomains-origin-response-${local.module_id}"
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }
}

resource "aws_iam_role" "lambda_edge_execution" {
  name               = "cloudfront-subdomains-lambda-edge-execution-${local.module_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_edge_execution.json

  tags = {
    Name              = "cloudfront-subdomains-lambda-edge-execution-${local.module_id}"
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }
}

data "aws_iam_policy_document" "lambda_edge_execution" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}

// Cloudfront

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  comment     = "Frontend per branch for ${var.hostname}"
  price_class = "PriceClass_100"
  aliases = [
    "branch.${var.hostname}",
    "*.branch.${var.hostname}",
  ]

  origin {
    domain_name = aws_s3_bucket.static_web.bucket_regional_domain_name
    origin_id   = "s3-static-web"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_bucket_static_web.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "s3-static-web"

    lambda_function_association {
      // 1. Handles AD callback.
      //
      // 2. Rewrites 'some-branch.branch.<hostname>/some-file' to
      // 'some-branch.branch.<hostname>/some-branch/some-file', to
      // target correct S3 bucket folder.
      //
      // viewer-request rather than the origin-request, so that the host name
      // contains the subfolder name (S3 origin hostname does not).
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.viewer_request.qualified_arn
    }

    lambda_function_association {
      // Handles file not found in S3, by redirecting to same url with query
      // param 'cloudfrontindex=true' to force viewer-request function to return
      // default object.
      event_type = "origin-response"
      lambda_arn = aws_lambda_function.origin_response.qualified_arn
    }

    min_ttl                = 0
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = aws_cloudfront_cache_policy.this.id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.branch.arn
    minimum_protocol_version = "TLSv1.2_2021"
    // sni-only: no dedicated IP that may incur extra charges.
    ssl_support_method = "sni-only"
  }

  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }

  lifecycle {
    ignore_changes = [
      web_acl_id
    ]
  }

  tags = {
    Name              = "branch.${var.hostname}"
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }

  depends_on = [aws_acm_certificate.branch]
}

resource "aws_cloudfront_cache_policy" "this" {
  name        = "cloudfront-subdomains-${local.module_id}"
  default_ttl = 50
  max_ttl     = 100
  min_ttl     = 1
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    // To access the query string in an origin request or origin response
    // function, your cache policy or origin request policy must be set to All
    // for Query strings.
    // https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-restrictions.html#function-restrictions-query-strings
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "s3_bucket_static_web" {}

// S3 Bucket

resource "aws_s3_bucket" "static_web" {
  bucket = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.project}-frontend-branch-${local.module_id}-${var.environment}"

  tags = {
    Name              = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.project}-frontend-branch-${local.module_id}-${var.environment}"
    Project           = var.project
    Environment       = var.environment
    TerraformModule   = "cloudfront-subdomains"
    TerraformModuleId = local.module_id
  }
}

resource "aws_s3_bucket_policy" "static_web" {
  bucket = aws_s3_bucket.static_web.id
  policy = data.aws_iam_policy_document.s3_bucket_static_web.json
}

data "aws_iam_policy_document" "s3_bucket_static_web" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.static_web.arn,
      "${aws_s3_bucket.static_web.arn}/*",
    ]

    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.s3_bucket_static_web.iam_arn,
      ]
    }
  }
}

resource "aws_s3_bucket_acl" "static_web" {
  bucket = aws_s3_bucket.static_web.id
  acl    = "private"
}

# Disable public access to bucket and contents
resource "aws_s3_bucket_public_access_block" "static_web" {
  bucket = aws_s3_bucket.static_web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Automatically delete contents after number of days
resource "aws_s3_bucket_lifecycle_configuration" "static_web" {
  bucket = aws_s3_bucket.static_web.id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = 60
    }
  }
}