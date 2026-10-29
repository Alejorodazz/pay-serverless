terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.bucket_tags,
  )

  frontend_bucket_name = coalesce(
    var.frontend_bucket,
    "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}",
  )

  cors_allow_origin = coalesce(
    var.cors_allow_origin,
    var.frontend_domain_name == null ? "*" : "https://${var.frontend_domain_name}",
  )

  secret_arns = concat(
    var.recurrente_secret_arn == null ? [] : [var.recurrente_secret_arn],
    var.recurrente_webhook_secret_arn == null ? [] : [var.recurrente_webhook_secret_arn],
    var.laravel_api_token_secret_arn == null ? [] : [var.laravel_api_token_secret_arn],
    var.cloudflare_api_token == null ? [] : [var.cloudflare_api_token]
  )

  lambda_sources = {
    create_checkout = {
      source_dir = "${path.module}/../functions/create_checkout"
      handler    = "handler.create_checkout_handler"
      timeout    = 30
      memory     = 256
    }
    payment_status = {
      source_dir = "${path.module}/../functions/payment_status"
      handler    = "handler.payment_status"
      timeout    = 15
      memory     = 256
    }
    payment_webhook = {
      source_dir = "${path.module}/../functions/payment_webhook"
      handler    = "handler.payment_webhook"
      timeout    = 30
      memory     = 256
    }
    provision_tenant = {
      source_dir = "${path.module}/../functions/provision_tenant"
      handler    = "handler.provision_tenant"
      timeout    = 60
      memory     = 256
    }
  }
}

data "archive_file" "lambda_package" {
  for_each = local.lambda_sources

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.root}/.terraform/${each.key}.zip"
}
