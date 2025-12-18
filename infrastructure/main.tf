terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state-bucket-superman-harry"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "qr_code_storage" {
  bucket = "qr-code-storage-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "QR Code Storage"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "qr_code_storage_lifecycle" {
  bucket = aws_s3_bucket.qr_code_storage.id

  rule {
    id     = "expire_objects"
    status = "Enabled"

    expiration {
      days = 1
    }
  }
}

resource "aws_s3_bucket_public_access_block" "qr_code_storage_pab" {
  bucket = aws_s3_bucket.qr_code_storage.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "qr_code_storage_policy" {
  bucket = aws_s3_bucket.qr_code_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.qr_code_storage.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.qr_code_storage_pab]
}

resource "aws_dynamodb_table" "qr_history" {
  name           = "QRHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "QR History Table"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "QRGeneratorLambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "QRGeneratorLambdaPolicy"
  description = "IAM policy for QR Generator Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.qr_code_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.qr_history.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "qr_generator" {
  filename         = "lambda_function.zip"
  function_name    = "QRGenerator"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("lambda_function.zip")
  runtime         = "python3.12"
  timeout         = 30

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.qr_code_storage.bucket
      DYNAMODB_TABLE = aws_dynamodb_table.qr_history.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
  ]
}

resource "aws_lambda_function_url" "qr_generator_url" {
  function_name      = aws_lambda_function.qr_generator.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive", "Content-Type"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for QR code storage"
  value       = aws_s3_bucket.qr_code_storage.bucket
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for QR history"
  value       = aws_dynamodb_table.qr_history.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.qr_generator.function_name
}

output "lambda_function_url" {
  description = "URL of the Lambda function"
  value       = aws_lambda_function_url.qr_generator_url.function_url
}