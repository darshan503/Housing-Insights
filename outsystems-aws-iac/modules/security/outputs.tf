output "alb_security_group_id" {
  description = "ALB security group."
  value       = aws_security_group.alb.id
}

output "frontend_security_group_id" {
  description = "Front-end security group."
  value       = aws_security_group.frontend.id
}

output "controller_security_group_id" {
  description = "Controller security group."
  value       = aws_security_group.controller.id
}

output "database_security_group_id" {
  description = "Database security group."
  value       = aws_security_group.database.id
}
