resource "aws_sqs_queue" "failed_events" {
  name                       = "${var.project_name}-${var.environment}-failed-events"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  tags                       = local.common_tags
}

resource "aws_sqs_queue" "processing_dlq" {
  name                      = "${var.project_name}-${var.environment}-processing-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "valid_events" {
  name                       = "${var.project_name}-${var.environment}-valid-events"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 180
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 5
  })

  tags = local.common_tags
}
