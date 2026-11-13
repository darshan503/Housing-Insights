variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for SNS and log groups."
  type        = string
}

variable "alarm_email" {
  description = "Optional e-mail subscriber."
  type        = string
  default     = ""
}

variable "log_group_prefix" {
  description = "Prefix of server log groups."
  type        = string
}

variable "log_retention_days" {
  description = "Log retention in days."
  type        = number
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix."
  type        = string
}

variable "frontend_asg_name" {
  description = "Front-end ASG name."
  type        = string
}

variable "controller_instance_id" {
  description = "Controller instance ID."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS identifier."
  type        = string
}

variable "db_allocated_storage_gb" {
  description = "Allocated DB storage, used to compute the free-storage threshold."
  type        = number
}
