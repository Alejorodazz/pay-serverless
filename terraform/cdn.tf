resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudflareToReadFrontend"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

resource "cloudflare_record" "frontend" {
  count = var.cloudflare_zone_id != null && var.frontend_domain_name != null ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.frontend_domain_name
  type    = "CNAME"
  content   = aws_s3_bucket.frontend.website_endpoint
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "api" {
  count = var.cloudflare_zone_id != null && var.api_custom_domain_name != null && var.api_certificate_arn != null ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.api_custom_domain_name
  type    = "CNAME"
  content   = aws_api_gateway_domain_name.payment[0].regional_domain_name
  proxied = true
  ttl     = 1
}
