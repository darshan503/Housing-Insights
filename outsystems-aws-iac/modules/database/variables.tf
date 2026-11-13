variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "engine" {
  description = "RDS SQL Server engine."
  type        = string

  validation {
    condition     = contains(["sqlserver-se", "sqlserver-ee"], var.engine)
    error_message = "engine must be sqlserver-se or sqlserver-ee (editions supported by OutSystems)."
  }
}

variable "engine_version" {
  description = "Engine version."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage (GiB)."
  type        = number
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)."
  type        = number

  validation {
    condition     = var.max_allocated_storage >= 20
    error_message = "max_allocated_storage must be at least 20 GiB."
  }
}

variable "multi_az" {
  description = "Multi-AZ deployment."
  type        = bool
}

variable "backup_retention_days" {
  description = "Automated backup retention."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = true
}

variable "enhanced_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 disables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enhanced_monitoring_interval)
    error_message = "enhanced_monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "timezone" {
  description = "SQL Server time zone."
  type        = string
  default     = "Singapore Standard Time"
}

variable "master_username" {
  description = "Master user name (password is generated and stored by RDS in Secrets Manager)."
  type        = string
  default     = "osadmin"
}

variable "kms_key_arn" {
  description = "KMS key for storage, PI and secret encryption."
  type        = string
}

variable "subnet_ids" {
  description = "Data subnet IDs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires subnets in at least two AZs."
  }
}

variable "security_group_id" {
  description = "Database security group."
  type        = string
}
