provider "aws" {
  region = "us-west-2"  # Change to your desired AWS region
}

# Random string for unique resource naming
resource "random_string" "random_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create S3 bucket with unique name
resource "aws_s3_bucket" "bucket" {
  bucket = "jira-tickets-${random_string.random_suffix.result}"
  
  tags = {
    Name = "MyS3Bucket"
  }
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Archive Lambda function (zip the source files) for start-glue-job
data "archive_file" "lambda_package_start_glue" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/start-glue-job"
  output_path = "${path.module}/lambda_function_start_glue_payload.zip"
}

# Archive Lambda function (zip the source files) for classify-tickets
data "archive_file" "lambda_package_classify_tickets" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/classify-tickets"
  output_path = "${path.module}/lambda_function_classify_tickets_payload.zip"
}

# Upload Glue ETL script to S3 (no zip)
resource "aws_s3_object" "etl_script_upload" {
  bucket = aws_s3_bucket.bucket.id
  key    = "scripts/etl_script.py"
  source = "${path.module}/../src/glue/etl_script.py"
}

# Create IAM Role for start-glue-job Lambda
resource "aws_iam_role" "lambda_role_start_glue" {
  name = "lambda_execution_role_start_glue_${random_string.random_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach IAM policy to allow Lambda to start Glue jobs and access S3 and CloudWatch logs
resource "aws_iam_role_policy" "lambda_policy_start_glue" {
  role = aws_iam_role.lambda_role_start_glue.id

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
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJob",
          "glue:GetJobRun"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.jira_etl_job.name}"
        ]
      }
    ]
  })
}

# Required data sources to get current region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Lambda function resource for start-glue-job
resource "aws_lambda_function" "start_glue_job_lambda" {
  function_name    = "start-glue-job-lambda-${random_string.random_suffix.result}"
  filename         = data.archive_file.lambda_package_start_glue.output_path
  handler          = "main.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role_start_glue.arn
  source_code_hash = data.archive_file.lambda_package_start_glue.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL     = "DEBUG"
      GLUE_JOB_NAME = aws_glue_job.jira_etl_job.name
    }
  }

  timeout     = 30
  memory_size = 128
}

# Create IAM Role for classify-tickets Lambda
resource "aws_iam_role" "lambda_role_classify_tickets" {
  name = "lambda_execution_role_classify_tickets_${random_string.random_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach IAM policy to allow classify-tickets Lambda to access S3 and CloudWatch logs
resource "aws_iam_role_policy" "lambda_policy_classify_tickets" {
  role = aws_iam_role.lambda_role_classify_tickets.id

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
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.bucket.arn}",
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function resource for classify-tickets
resource "aws_lambda_function" "classify_tickets_lambda" {
  function_name    = "classify-tickets-lambda-${random_string.random_suffix.result}"
  filename         = data.archive_file.lambda_package_classify_tickets.output_path
  handler          = "main.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role_classify_tickets.arn
  source_code_hash = data.archive_file.lambda_package_classify_tickets.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = "DEBUG"
      BUCKET_NAME = aws_s3_bucket.bucket.id
    }
  }

  timeout     = 120
  memory_size = 128
}

# Lambda Permission for S3 to invoke the start-glue-job function
resource "aws_lambda_permission" "allow_s3_invoke_start_glue" {
  statement_id  = "AllowExecutionFromS3ForStartGlue"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_glue_job_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket.arn
}

# Lambda Permission for S3 to invoke the classify-tickets function
resource "aws_lambda_permission" "allow_s3_invoke_classify_tickets" {
  statement_id  = "AllowExecutionFromS3ForClassifyTickets"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.classify_tickets_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket.arn
}

# S3 Bucket Notification for both Lambda functions
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_glue_job_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "unprocessed/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.classify_tickets_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "staged/"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_invoke_start_glue,
    aws_lambda_permission.allow_s3_invoke_classify_tickets
  ]
}

# IAM Role for Glue Job
resource "aws_iam_role" "glue_service_role" {
  name = "glue-service-role-${random_string.random_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM Policy for Glue Job
resource "aws_iam_role_policy" "glue_policy" {
  role = aws_iam_role.glue_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_s3_bucket.bucket.arn}",
          "${aws_s3_bucket.bucket.arn}/*",
          "arn:aws:logs:*:*:*"
        ]
      }
    ]
  })
}

# Glue ETL Job resource
resource "aws_glue_job" "jira_etl_job" {
  name        = "jira-etl-${random_string.random_suffix.result}"
  role_arn    = aws_iam_role.glue_service_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.bucket.bucket}/scripts/etl_script.py"
    python_version  = "3"
  }
  
  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-enable"
  }
  
  max_retries     = 0
  glue_version    = "4.0"
  worker_type     = "G.1X"
  number_of_workers = 2
  timeout         = 10
  tags = {
    Name = "JiraETLJob"
  }
}

# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "start_glue_job_lambda_arn" {
  value = aws_lambda_function.start_glue_job_lambda.arn
}

output "classify_tickets_lambda_arn" {
  value = aws_lambda_function.classify_tickets_lambda.arn
}

output "glue_job_name" {
  value = aws_glue_job.jira_etl_job.name
}