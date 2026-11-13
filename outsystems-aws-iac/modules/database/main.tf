###############################################################################
# Amazon RDS for SQL Server hosting the OutSystems Platform, Session and
# Logging catalogs. The Configuration Tool creates the catalogs/users using
# the master credentials stored (and rotated) in Secrets Manager by RDS.
###############################################################################
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-sqlserver"
  description = "Isolated data subnets for OutSystems database"
  subnet_ids  = var.subnet_ids
}

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  name = "${var.name_prefix}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-sqlserver"
  engine         = var.engine
  engine_version = var.engine_version
  license_model  = "license-included"
  instance_class = var.instance_class

  # OutSystems requires a case-insensitive collation.
  character_set_name = "SQL_Latin1_General_CP1_CI_AS"
  timezone           = var.timezone

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = 1433

  backup_retention_period   = var.backup_retention_days
  backup_window             = "17:00-18:00"         # 01:00-02:00 SGT
  maintenance_window        = "sun:18:30-sun:19:30" # Mon 02:30-03:30 SGT
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-sqlserver-final"

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["agent", "error"]

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  monitoring_interval = var.enhanced_monitoring_interval
  monitoring_role_arn = var.enhanced_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  tags = { Name = "${var.name_prefix}-sqlserver" }
}
