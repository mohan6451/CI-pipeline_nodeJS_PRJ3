output "state_bucket_name" {
  description = "S3 bucket name for Terraform state — paste into backend config"
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking — paste into backend config"
  value       = aws_dynamodb_table.lock.name
}

output "aws_region" {
  value = var.aws_region
}
