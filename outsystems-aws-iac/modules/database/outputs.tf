output "identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "address" {
  description = "RDS endpoint host name."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}
