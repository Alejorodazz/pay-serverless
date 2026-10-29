resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_sources

  name              = "/aws/lambda/${var.project_name}-${var.environment}-${each.key}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_function" "create_checkout" {
  function_name    = "${var.project_name}-${var.environment}-create-checkout"
  filename         = data.archive_file.lambda_package["create_checkout"].output_path
  source_code_hash = data.archive_file.lambda_package["create_checkout"].output_base64sha256
  handler          = local.lambda_sources.create_checkout.handler
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = local.lambda_sources.create_checkout.timeout
  memory_size      = local.lambda_sources.create_checkout.memory

  environment {
    variables = {
      APP_ENV                 = var.environment
      PROJECT_NAME            = var.project_name
      PAYMENT_TABLE_NAME      = aws_dynamodb_table.payment_status.name
      IDEMPOTENCY_TABLE_NAME  = aws_dynamodb_table.idempotency.name
      RECURRENTE_SECRET_ARN   = coalesce(var.recurrente_secret_arn, "")
      RECURRENTE_API_BASE_URL = var.recurrente_api_base_url
      RECURRENTE_SUCCESS_URL  = var.recurrente_success_url
      RECURRENTE_CANCEL_URL   = var.recurrente_cancel_url
      DEFAULT_CURRENCY        = var.checkout_default_currency
      PRODUCT_NAME            = var.checkout_product_name
    }
  }

  depends_on = [aws_iam_role_policy.lambda_runtime]
  tags       = local.common_tags
}

resource "aws_lambda_function" "payment_status" {
  function_name    = "${var.project_name}-${var.environment}-payment-status"
  filename         = data.archive_file.lambda_package["payment_status"].output_path
  source_code_hash = data.archive_file.lambda_package["payment_status"].output_base64sha256
  handler          = local.lambda_sources.payment_status.handler
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = local.lambda_sources.payment_status.timeout
  memory_size      = local.lambda_sources.payment_status.memory

  environment {
    variables = {
      APP_ENV            = var.environment
      PROJECT_NAME       = var.project_name
      PAYMENT_TABLE_NAME = aws_dynamodb_table.payment_status.name
    }
  }

  depends_on = [aws_iam_role_policy.lambda_runtime]
  tags       = local.common_tags
}

resource "aws_lambda_function" "payment_webhook" {
  function_name    = "${var.project_name}-${var.environment}-payment-webhook"
  filename         = data.archive_file.lambda_package["payment_webhook"].output_path
  source_code_hash = data.archive_file.lambda_package["payment_webhook"].output_base64sha256
  handler          = local.lambda_sources.payment_webhook.handler
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = local.lambda_sources.payment_webhook.timeout
  memory_size      = local.lambda_sources.payment_webhook.memory

  environment {
    variables = {
      APP_ENV                       = var.environment
      PROJECT_NAME                  = var.project_name
      PAYMENT_TABLE_NAME            = aws_dynamodb_table.payment_status.name
      IDEMPOTENCY_TABLE_NAME        = aws_dynamodb_table.idempotency.name
      VALID_QUEUE_URL               = aws_sqs_queue.valid_events.url
      FAILED_QUEUE_URL              = aws_sqs_queue.failed_events.url
      RECURRENTE_SECRET_ARN         = coalesce(var.recurrente_secret_arn, "")
      RECURRENTE_WEBHOOK_SECRET_ARN = coalesce(var.recurrente_webhook_secret_arn, "")
      RECURRENTE_API_BASE_URL       = var.recurrente_api_base_url
      WEBHOOK_SIGNATURE_HEADER      = "svix-signature"
    }
  }

  depends_on = [aws_iam_role_policy.lambda_runtime]
  tags       = local.common_tags
}

resource "aws_lambda_function" "provision_tenant" {
  function_name    = "${var.project_name}-${var.environment}-provision-tenant"
  filename         = data.archive_file.lambda_package["provision_tenant"].output_path
  source_code_hash = data.archive_file.lambda_package["provision_tenant"].output_base64sha256
  handler          = local.lambda_sources.provision_tenant.handler
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = local.lambda_sources.provision_tenant.timeout
  memory_size      = local.lambda_sources.provision_tenant.memory

  environment {
    variables = {
      APP_ENV                      = var.environment
      PROJECT_NAME                 = var.project_name
      PAYMENT_TABLE_NAME           = aws_dynamodb_table.payment_status.name
      IDEMPOTENCY_TABLE_NAME       = aws_dynamodb_table.idempotency.name
      LARAVEL_API_BASE_URL         = coalesce(var.laravel_api_base_url, "")
      LARAVEL_API_PROVISION_PATH   = var.laravel_api_provision_path
      LARAVEL_API_TOKEN_SECRET_ARN = coalesce(var.laravel_api_token_secret_arn, "")
    }
  }

  depends_on = [aws_iam_role_policy.lambda_runtime]
  tags       = local.common_tags
}

resource "aws_lambda_event_source_mapping" "provision_tenant" {
  event_source_arn                   = aws_sqs_queue.valid_events.arn
  function_name                      = aws_lambda_function.provision_tenant.arn
  batch_size                         = var.event_batch_size
  maximum_batching_window_in_seconds = var.event_max_batching_window_seconds
  function_response_types            = ["ReportBatchItemFailures"]
  enabled                            = true
}
