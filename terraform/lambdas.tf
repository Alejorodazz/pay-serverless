resource "aws_lambda_function" "create_checkout" {
  function_name = "create_checkout_function"
  filename      = "${path.root}/functions/create_checkout/handler.zip"
  handler       = "handler.create_checkout_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      AWS_REGION = var.aws_region
    }
  }
}