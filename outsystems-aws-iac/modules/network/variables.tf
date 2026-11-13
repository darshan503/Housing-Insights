variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "aws_region" {
  description = "Region (used for the S3 endpoint service name)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "availability_zones" {
  description = "AZs to create subnets in."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across AZs."
  type        = bool
}

variable "flow_log_retention_days" {
  description = "Retention of the VPC flow log group."
  type        = number
}

variable "kms_key_arn" {
  description = "KMS key encrypting the flow log group."
  type        = string
}
