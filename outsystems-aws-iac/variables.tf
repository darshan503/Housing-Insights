###############################################################################
# General
###############################################################################
variable "project_name" {
  description = "Short project identifier used as a prefix for every resource name."
  type        = string
  default     = "housinginsights"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.project_name))
    error_message = "project_name must be 2-16 chars, lowercase letters, digits or hyphens, starting with a letter (ALB/TG names are limited to 32 chars)."
  }
}

variable "environment" {
  description = "OutSystems environment this stack hosts. OutSystems recommends isolated Dev / Test / Prod environments plus a dedicated LifeTime environment."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod", "lifetime"], var.environment)
    error_message = "environment must be one of: dev, test, prod, lifetime."
  }
}

variable "owner" {
  description = "Team or person responsible for the stack (used for tagging)."
  type        = string
  default     = "platform-team"
}

variable "aws_region" {
  description = "AWS region to deploy to."
  type        = string
  default     = "ap-southeast-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. ap-southeast-1."
  }
}

###############################################################################
# Network
###############################################################################
variable "vpc_cidr" {
  description = "CIDR block of the environment VPC (a /16 is expected; subnets are carved as /24s)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix of /20 or larger (e.g. 10.10.0.0/16)."
  }
}

variable "availability_zones" {
  description = "Availability zones to spread the platform across (minimum 2 for ALB and RDS subnet groups)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "Provide 2 or 3 availability zones."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheaper, non-prod) instead of one per AZ (highly available)."
  type        = bool
  default     = true
}

variable "management_cidr_blocks" {
  description = "CIDRs (e.g. LifeTime environment NAT IPs, corporate VPN) allowed to reach /ServiceCenter and /LifeTime through the public ALB. Everyone else gets HTTP 403."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.management_cidr_blocks) <= 3 && alltrue([for c in var.management_cidr_blocks : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "management_cidr_blocks accepts at most 3 valid CIDRs and must not contain 0.0.0.0/0."
  }
}

###############################################################################
# Edge / load balancing
###############################################################################
variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate served by the HTTPS listener of the ALB."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be a valid ACM certificate ARN."
  }
}

variable "health_check_path" {
  description = "Path used by the ALB target-group health check. Point it to a lightweight, anonymous OutSystems screen/endpoint."
  type        = string
  default     = "/SingaporeHousingInsights/"
}

variable "outsystems_modules" {
  description = "OutSystems modules (eSpaces) published to this environment. All modules share the same farm; only modules with expose_url=true are reachable by end users."
  type = map(object({
    layer       = string
    description = string
    expose_url  = bool
  }))
  default = {
    SingaporeHousingInsights = {
      layer       = "end-user"
      description = "Frontend and user interaction (Reactive UI)"
      expose_url  = true
    }
    HousingInsights_core = {
      layer       = "core"
      description = "Data model (ResaleTransaction) and business logic"
      expose_url  = false
    }
    HousingInsights_integration = {
      layer       = "integration"
      description = "External API communication with https://data.gov.sg (egress via NAT gateway)"
      expose_url  = false
    }
  }

  validation {
    condition     = alltrue([for m in values(var.outsystems_modules) : contains(["end-user", "core", "integration", "library"], m.layer)])
    error_message = "Each module layer must be one of end-user, core, integration, library (OutSystems Architecture Canvas)."
  }
}

variable "enable_waf" {
  description = "Attach an AWS WAFv2 web ACL (managed rule sets + rate limiting) to the ALB."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per source IP before WAF blocks it."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100
    error_message = "waf_rate_limit must be at least 100 (AWS minimum)."
  }
}

###############################################################################
# OutSystems servers
###############################################################################
variable "controller_instance_type" {
  description = "EC2 instance type of the Deployment Controller server."
  type        = string
  default     = "m6i.xlarge"
}

variable "frontend_instance_type" {
  description = "EC2 instance type of the front-end servers."
  type        = string
  default     = "m6i.xlarge"
}

variable "frontend_min_size" {
  description = "Minimum number of front-end servers."
  type        = number
  default     = 2

  validation {
    condition     = var.frontend_min_size >= 1
    error_message = "frontend_min_size must be at least 1."
  }
}

variable "frontend_max_size" {
  description = "Maximum number of front-end servers."
  type        = number
  default     = 4
}

variable "frontend_desired_capacity" {
  description = "Desired number of front-end servers."
  type        = number
  default     = 2
}

variable "ami_id" {
  description = "Optional explicit Windows Server AMI. When empty, the latest Windows Server 2022 Base AMI is resolved from SSM."
  type        = string
  default     = ""
}

variable "platform_installer_s3_key" {
  description = "Optional S3 key (inside the artifacts bucket) of the OutSystems Platform Server installer. When set, servers download and silently install it at boot."
  type        = string
  default     = ""
}

###############################################################################
# Database (Amazon RDS for SQL Server)
###############################################################################
variable "db_engine" {
  description = "RDS SQL Server edition. OutSystems supports SQL Server Standard and Enterprise."
  type        = string
  default     = "sqlserver-se"

  validation {
    condition     = contains(["sqlserver-se", "sqlserver-ee"], var.db_engine)
    error_message = "db_engine must be sqlserver-se or sqlserver-ee."
  }
}

variable "db_engine_version" {
  description = "SQL Server major version for RDS (e.g. 15.00 = SQL Server 2019, 16.00 = 2022)."
  type        = string
  default     = "15.00"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.m6i.xlarge"
}

variable "db_allocated_storage" {
  description = "Initial storage (GiB)."
  type        = number
  default     = 100

  validation {
    condition     = var.db_allocated_storage >= 20
    error_message = "db_allocated_storage must be at least 20 GiB for SQL Server."
  }
}

variable "db_max_allocated_storage" {
  description = "Upper limit (GiB) for RDS storage autoscaling."
  type        = number
  default     = 500
}

variable "db_multi_az" {
  description = "Deploy the database as Multi-AZ (synchronous standby in a second AZ)."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "Automated backup retention (days)."
  type        = number
  default     = 14

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days must be between 1 and 35."
  }
}

variable "db_performance_insights_enabled" {
  description = "Enable RDS Performance Insights (not supported on every instance class)."
  type        = bool
  default     = true
}

###############################################################################
# Operations
###############################################################################
variable "alarm_email" {
  description = "Optional e-mail address subscribed to the alarm SNS topic."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be empty or a valid e-mail address."
  }
}

variable "log_retention_days" {
  description = "Retention (days) for CloudWatch log groups."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value supported by CloudWatch Logs."
  }
}
