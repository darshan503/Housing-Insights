output "artifacts_bucket_name" {
  description = "Artifacts bucket name."
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "Artifacts bucket ARN."
  value       = aws_s3_bucket.artifacts.arn
}

output "logs_bucket_name" {
  description = "Logs bucket name."
  value       = aws_s3_bucket.logs.bucket
}
