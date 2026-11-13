variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "is_production" {
  description = "Enables deletion/termination protection."
  type        = bool
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets for the ALB."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subnets for OutSystems servers."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group."
  type        = string
}

variable "frontend_security_group" {
  description = "Front-end security group."
  type        = string
}

variable "controller_security_group" {
  description = "Controller security group."
  type        = string
}

variable "acm_certificate_arn" {
  description = "Certificate for the HTTPS listener."
  type        = string
}

variable "health_check_path" {
  description = "Target-group health check path."
  type        = string
}

variable "management_cidr_blocks" {
  description = "CIDRs allowed to reach Service Center / LifeTime through the ALB."
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Attach a WAF web ACL."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Per-IP request limit per 5 minutes."
  type        = number
  default     = 2000
}

variable "ami_id" {
  description = "Explicit AMI (empty = latest Windows Server 2022)."
  type        = string
  default     = ""
}

variable "controller_instance_type" {
  description = "Controller instance type."
  type        = string
}

variable "frontend_instance_type" {
  description = "Front-end instance type."
  type        = string
}

variable "frontend_min_size" {
  description = "ASG minimum."
  type        = number
}

variable "frontend_max_size" {
  description = "ASG maximum."
  type        = number
}

variable "frontend_desired_capacity" {
  description = "ASG desired."
  type        = number
}

variable "kms_key_arn" {
  description = "Platform KMS key."
  type        = string
}

variable "artifacts_bucket_name" {
  description = "Artifacts bucket name."
  type        = string
}

variable "artifacts_bucket_arn" {
  description = "Artifacts bucket ARN."
  type        = string
}

variable "logs_bucket_name" {
  description = "Bucket receiving ALB access logs."
  type        = string
}

variable "platform_installer_s3_key" {
  description = "S3 key of the Platform Server installer (optional)."
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "RDS endpoint."
  type        = string
}

variable "db_secret_arn" {
  description = "RDS master secret ARN (may be null before the DB exists)."
  type        = string
  default     = null
}

variable "log_group_prefix" {
  description = "CloudWatch log group prefix used by the CloudWatch agent."
  type        = string
}
