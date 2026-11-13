###############################################################################
# OutSystems 11 (self-managed) platform on AWS - one environment per state.
#
#  Internet ──► WAF ──► ALB (public subnets, TLS 1.2+)
#                          │ HTTPS 443
#                          ▼
#               Front-end ASG (private app subnets)  ◄──12001── Deployment Controller
#                  │  12000 / 5672 ──────────────────────────►  (private app subnet)
#                  ▼ 1433                                          │ 1433
#               RDS SQL Server Multi-AZ (isolated data subnets) ◄──┘
###############################################################################

locals {
  name_prefix      = "${var.project_name}-${var.environment}"
  is_production    = var.environment == "prod"
  log_group_prefix = "/outsystems/${local.name_prefix}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Application = "OutSystems"
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

module "network" {
  source = "./modules/network"

  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  vpc_cidr                = var.vpc_cidr
  availability_zones      = var.availability_zones
  single_nat_gateway      = var.single_nat_gateway
  flow_log_retention_days = var.log_retention_days
  kms_key_arn             = aws_kms_key.platform.arn
}

module "storage" {
  source = "./modules/storage"

  name_prefix        = local.name_prefix
  account_id         = data.aws_caller_identity.current.account_id
  kms_key_arn        = aws_kms_key.platform.arn
  log_retention_days = var.log_retention_days
  force_destroy      = !local.is_production
}

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}

module "database" {
  source = "./modules/database"

  name_prefix                  = local.name_prefix
  engine                       = var.db_engine
  engine_version               = var.db_engine_version
  instance_class               = var.db_instance_class
  allocated_storage            = var.db_allocated_storage
  max_allocated_storage        = var.db_max_allocated_storage
  multi_az                     = var.db_multi_az
  backup_retention_days        = var.db_backup_retention_days
  deletion_protection          = local.is_production
  skip_final_snapshot          = !local.is_production
  performance_insights_enabled = var.db_performance_insights_enabled
  kms_key_arn                  = aws_kms_key.platform.arn
  subnet_ids                   = module.network.data_subnet_ids
  security_group_id            = module.security.database_security_group_id
}

module "platform" {
  source = "./modules/platform"

  name_prefix               = local.name_prefix
  environment               = var.environment
  is_production             = local.is_production
  vpc_id                    = module.network.vpc_id
  public_subnet_ids         = module.network.public_subnet_ids
  app_subnet_ids            = module.network.app_subnet_ids
  alb_security_group_id     = module.security.alb_security_group_id
  frontend_security_group   = module.security.frontend_security_group_id
  controller_security_group = module.security.controller_security_group_id
  acm_certificate_arn       = var.acm_certificate_arn
  health_check_path         = var.health_check_path
  management_cidr_blocks    = var.management_cidr_blocks
  enable_waf                = var.enable_waf
  waf_rate_limit            = var.waf_rate_limit
  ami_id                    = var.ami_id
  controller_instance_type  = var.controller_instance_type
  frontend_instance_type    = var.frontend_instance_type
  frontend_min_size         = var.frontend_min_size
  frontend_max_size         = var.frontend_max_size
  frontend_desired_capacity = var.frontend_desired_capacity
  kms_key_arn               = aws_kms_key.platform.arn
  artifacts_bucket_name     = module.storage.artifacts_bucket_name
  artifacts_bucket_arn      = module.storage.artifacts_bucket_arn
  logs_bucket_name          = module.storage.logs_bucket_name
  platform_installer_s3_key = var.platform_installer_s3_key
  db_endpoint               = module.database.address
  db_secret_arn             = module.database.master_user_secret_arn
  log_group_prefix          = local.log_group_prefix

  depends_on = [module.storage]
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix             = local.name_prefix
  kms_key_arn             = aws_kms_key.platform.arn
  alarm_email             = var.alarm_email
  log_group_prefix        = local.log_group_prefix
  log_retention_days      = var.log_retention_days
  alb_arn_suffix          = module.platform.alb_arn_suffix
  target_group_arn_suffix = module.platform.target_group_arn_suffix
  frontend_asg_name       = module.platform.frontend_asg_name
  controller_instance_id  = module.platform.controller_instance_id
  db_instance_identifier  = module.database.identifier
  db_allocated_storage_gb = var.db_allocated_storage
}
