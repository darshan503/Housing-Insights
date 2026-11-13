output "alb_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch dimension)."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch dimension)."
  value       = aws_lb_target_group.frontend.arn_suffix
}

output "frontend_asg_name" {
  description = "Front-end ASG name."
  value       = aws_autoscaling_group.frontend.name
}

output "controller_instance_id" {
  description = "Controller instance ID."
  value       = aws_instance.controller.id
}

output "controller_private_ip" {
  description = "Controller private IP."
  value       = aws_instance.controller.private_ip
}

output "web_acl_arn" {
  description = "WAF web ACL ARN (null when disabled)."
  value       = try(aws_wafv2_web_acl.this[0].arn, null)
}
