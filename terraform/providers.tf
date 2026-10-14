provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = ["~/Usuario/.aws/credentials"]
}