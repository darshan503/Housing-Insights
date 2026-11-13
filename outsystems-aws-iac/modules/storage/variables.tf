variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "account_id" {
  description = "AWS account ID (makes bucket names globally unique)."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the artifacts bucket."
  type        = string
}

variable "log_retention_days" {
  description = "Days to keep ALB access logs."
  type        = number
}

variable "force_destroy" {
  description = "Allow deleting non-empty buckets (non-prod only)."
  type        = bool
  default     = false
}
