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

/*
resource "cloudflare_record" "frontend" {
  count = var.cloudflare_zone_id != null && var.frontend_domain_name != null ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.frontend_domain_name
  type    = "CNAME"
  value   = aws_s3_bucket.frontend.website_endpoint
  proxied = true
  ttl     = 1
}
*/


resource "cloudflare_worker_script" "s3_proxy" {
  account_id = var.cloudflare_account_id
  name       = var.worker_script_name
  module     = true

  plain_text_binding {
    name = "S3_BUCKET"
    text = aws_s3_bucket.frontend.id
  }

  plain_text_binding {
    name = "S3_REGION"
    text = var.aws_region
  }

  content = <<EOF
export default {
  async fetch(request, env) {
    if (!["GET", "HEAD"].includes(request.method)) {
      return new Response("Method not allowed", {
        status: 405,
        headers: { Allow: "GET, HEAD" },
      });
    }

    const incoming = new URL(request.url);
    const path = incoming.pathname === "/"
      ? "/index.html"
      : incoming.pathname;

    const origin = new URL(
      "https://s3." + env.S3_REGION + ".amazonaws.com"
    );

    origin.pathname = "/" + env.S3_BUCKET + path;
    origin.search = incoming.search;

    return fetch(origin.toString(), {
      method: request.method,
      redirect: "manual",
    });
  },
};
EOF
}

resource "cloudflare_worker_domain" "pay_domain" {
  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  hostname   = var.frontend_domain_name
  service    = cloudflare_worker_script.s3_proxy.name
}

resource "cloudflare_record" "api" {
  count = var.cloudflare_zone_id != null && var.api_custom_domain_name != null && var.api_certificate_arn != null ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.api_custom_domain_name
  type    = "CNAME"
  value   = aws_api_gateway_domain_name.payment[0].regional_domain_name
  proxied = true
  ttl     = 1
}
