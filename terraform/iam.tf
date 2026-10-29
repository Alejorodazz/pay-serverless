data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-${var.environment}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "lambda_runtime" {
  name = "${var.project_name}-${var.environment}-lambda-runtime"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "WriteLambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-${var.environment}-*:*"
      },
      {
        Sid    = "PaymentState"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
        ]
        Resource = aws_dynamodb_table.payment_status.arn
      },
      {
        Sid    = "IdempotencyState"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.idempotency.arn
      },
      {
        Sid    = "PublishPaymentEvents"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:SendMessage",
        ]
        Resource = [
          aws_sqs_queue.valid_events.arn,
          aws_sqs_queue.failed_events.arn,
        ]
      },
      {
        Sid    = "ConsumeValidPaymentEvents"
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
        ]
        Resource = aws_sqs_queue.valid_events.arn
      },
      ], length(local.secret_arns) == 0 ? [] : [{
        Sid      = "ReadServiceSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [for arn in local.secret_arns : arn if can(regex("^arn:aws:", arn))]
    }])
  })
}
