resource "aws_api_gateway_rest_api" "payment" {
  name        = "${var.project_name}-${var.environment}"
  description = "Payment Gateway Serverless API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "checkout" {
  rest_api_id = aws_api_gateway_rest_api.payment.id
  parent_id   = aws_api_gateway_rest_api.payment.root_resource_id
  path_part   = "checkout"
}

resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.payment.id
  parent_id   = aws_api_gateway_rest_api.payment.root_resource_id
  path_part   = "estado"
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.payment.id
  parent_id   = aws_api_gateway_rest_api.payment.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_resource" "recurring_webhook" {
  rest_api_id = aws_api_gateway_rest_api.payment.id
  parent_id   = aws_api_gateway_resource.webhook.id
  path_part   = "recurrente"
}

resource "aws_api_gateway_method" "checkout_post" {
  rest_api_id   = aws_api_gateway_rest_api.payment.id
  resource_id   = aws_api_gateway_resource.checkout.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "checkout" {
  rest_api_id             = aws_api_gateway_rest_api.payment.id
  resource_id             = aws_api_gateway_resource.checkout.id
  http_method             = aws_api_gateway_method.checkout_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_checkout.invoke_arn
}

resource "aws_api_gateway_method" "status_get" {
  rest_api_id   = aws_api_gateway_rest_api.payment.id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.payment_id" = false
  }
}

resource "aws_api_gateway_integration" "status" {
  rest_api_id             = aws_api_gateway_rest_api.payment.id
  resource_id             = aws_api_gateway_resource.status.id
  http_method             = aws_api_gateway_method.status_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.payment_status.invoke_arn
}

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.payment.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook" {
  rest_api_id             = aws_api_gateway_rest_api.payment.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.payment_webhook.invoke_arn
}

resource "aws_api_gateway_method" "recurring_webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.payment.id
  resource_id   = aws_api_gateway_resource.recurring_webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "recurring_webhook" {
  rest_api_id             = aws_api_gateway_rest_api.payment.id
  resource_id             = aws_api_gateway_resource.recurring_webhook.id
  http_method             = aws_api_gateway_method.recurring_webhook_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.payment_webhook.invoke_arn
}

locals {
  cors_resources = {
    checkout          = aws_api_gateway_resource.checkout.id
    status            = aws_api_gateway_resource.status.id
    webhook           = aws_api_gateway_resource.webhook.id
    recurring_webhook = aws_api_gateway_resource.recurring_webhook.id
  }
}

resource "aws_api_gateway_method" "cors" {
  for_each = local.cors_resources

  rest_api_id   = aws_api_gateway_rest_api.payment.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors" {
  for_each = local.cors_resources

  rest_api_id = aws_api_gateway_rest_api.payment.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "cors" {
  for_each = local.cors_resources

  rest_api_id = aws_api_gateway_rest_api.payment.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors" {
  for_each = local.cors_resources

  rest_api_id = aws_api_gateway_rest_api.payment.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = aws_api_gateway_method_response.cors[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${local.cors_allow_origin}'"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  for_each = {
    checkout = aws_lambda_function.create_checkout
    status   = aws_lambda_function.payment_status
    webhook  = aws_lambda_function.payment_webhook
  }

  statement_id  = "AllowApiGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.payment.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "payment" {
  rest_api_id = aws_api_gateway_rest_api.payment.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.checkout.id,
      aws_api_gateway_resource.status.id,
      aws_api_gateway_resource.webhook.id,
      aws_api_gateway_resource.recurring_webhook.id,
      aws_api_gateway_integration.checkout.id,
      aws_api_gateway_integration.status.id,
      aws_api_gateway_integration.webhook.id,
      aws_api_gateway_integration.recurring_webhook.id,
      aws_api_gateway_integration.cors,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.checkout,
    aws_api_gateway_integration.status,
    aws_api_gateway_integration.webhook,
    aws_api_gateway_integration.recurring_webhook,
    aws_api_gateway_integration_response.cors,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "payment" {
  rest_api_id          = aws_api_gateway_rest_api.payment.id
  deployment_id        = aws_api_gateway_deployment.payment.id
  stage_name           = var.environment
  xray_tracing_enabled = true
  tags                 = local.common_tags
}

resource "aws_api_gateway_domain_name" "payment" {
  count = var.api_custom_domain_name != null && var.api_certificate_arn != null ? 1 : 0

  domain_name              = var.api_custom_domain_name
  regional_certificate_arn = var.api_certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  security_policy = "TLS_1_2"
}

resource "aws_api_gateway_base_path_mapping" "payment" {
  count = length(aws_api_gateway_domain_name.payment)

  api_id      = aws_api_gateway_rest_api.payment.id
  stage_name  = aws_api_gateway_stage.payment.stage_name
  domain_name = aws_api_gateway_domain_name.payment[0].domain_name
}
