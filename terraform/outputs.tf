output "api_base_url" {
  description = "URL base regional del API Gateway."
  value       = "https://${aws_api_gateway_rest_api.payment.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.payment.stage_name}"
}

output "api_custom_domain_url" {
  description = "URL del dominio personalizado de API cuando fue configurado."
  value       = var.api_custom_domain_name == null ? null : "https://${var.api_custom_domain_name}"
}

output "frontend_bucket_name" {
  description = "Nombre del bucket privado que recibe el build de React."
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_url" {
  description = "URL pública del frontend detrás de Cloudflare cuando se configuró el dominio."
  value       = var.frontend_domain_name == null ? "http://${aws_s3_bucket.frontend.website_endpoint}" : "https://${var.frontend_domain_name}"
}

output "valid_events_queue_url" {
  description = "URL de la cola de eventos válidos."
  value       = aws_sqs_queue.valid_events.url
}

output "failed_events_queue_url" {
  description = "URL de la cola de eventos fallidos."
  value       = aws_sqs_queue.failed_events.url
}

output "payment_status_table_name" {
  description = "Tabla DynamoDB para el estado del pago."
  value       = aws_dynamodb_table.payment_status.name
}
