terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for state files (Using your AWS account ID for unique bucket naming)
resource "aws_s3_bucket" "tf_state" {
  bucket        = "devops-tfstate-631412642519-lab1"
  force_destroy = true # Set to true so you can tear down easily at the end of the lab
}

# Enable Versioning for state recovery
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DynamoDB table for concurrency locking
resource "aws_dynamodb_table" "tf_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.tf_state.id
  description = "Name of the created S3 bucket for Terraform state"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.tf_locks.id
  description = "Name of the created DynamoDB locking table"
}
