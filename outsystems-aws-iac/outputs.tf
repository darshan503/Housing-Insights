output "environment_url" {
  description = "Public DNS name of the ALB. Create a CNAME/alias from your domain (matching the ACM certificate) to this."
  value       = "https://${module.platform.alb_dns_name}"
}

output "application_urls" {
  description = "End-user URLs of the OutSystems modules exposed through the ALB."
  value = {
    for name, m in var.outsystems_modules :
    name => "https://${module.platform.alb_dns_name}/${name}/" if m.expose_url
  }
}

output "outsystems_modules" {
  description = "Modules hosted by this environment and their architecture layer."
  value       = { for name, m in var.outsystems_modules : name => m.layer }
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.platform.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "controller_instance_id" {
  description = "Deployment Controller EC2 instance ID."
  value       = module.platform.controller_instance_id
}

output "frontend_asg_name" {
  description = "Front-end Auto Scaling Group name."
  value       = module.platform.frontend_asg_name
}

output "db_endpoint" {
  description = "RDS SQL Server endpoint used in the OutSystems Configuration Tool."
  value       = module.database.address
}

output "db_master_secret_arn" {
  description = "Secrets Manager secret holding the RDS master credentials (managed and rotated by RDS)."
  value       = module.database.master_user_secret_arn
}

output "artifacts_bucket" {
  description = "Bucket for Platform Server installers, server.hsconf and native SQL backups."
  value       = module.storage.artifacts_bucket_name
}

output "alarm_topic_arn" {
  description = "SNS topic receiving CloudWatch alarms."
  value       = module.monitoring.alarm_topic_arn
}

output "service_center_tunnel_command" {
  description = "Open Service Center on the controller through SSM (no RDP / public exposure required), then browse https://localhost:8443/ServiceCenter."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${module.platform.controller_instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=443,localPortNumber=8443"
}
