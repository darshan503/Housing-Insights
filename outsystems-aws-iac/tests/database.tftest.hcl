# Unit tests for modules/database.
mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name_prefix                  = "hi-unit"
  engine                       = "sqlserver-se"
  engine_version               = "15.00"
  instance_class               = "db.m6i.large"
  allocated_storage            = 100
  max_allocated_storage        = 500
  multi_az                     = true
  backup_retention_days        = 14
  deletion_protection          = true
  skip_final_snapshot          = false
  performance_insights_enabled = true
  kms_key_arn                  = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
  subnet_ids                   = ["subnet-aaaa", "subnet-bbbb"]
  security_group_id            = "sg-0123456789abcdef0"
}

run "production_database_is_secure_and_resilient" {
  command = apply
  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && aws_db_instance.this.kms_key_id == var.kms_key_arn
    error_message = "Database storage must be encrypted with the platform KMS key."
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "Database must not be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "Master password must be generated and managed by RDS/Secrets Manager (no plaintext passwords in state)."
  }

  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.deletion_protection
    error_message = "Production settings (Multi-AZ, deletion protection) were not applied."
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == "hi-unit-sqlserver-final"
    error_message = "A final snapshot must be taken when skip_final_snapshot is false."
  }

  assert {
    condition     = endswith(aws_db_instance.this.character_set_name, "_CI_AS")
    error_message = "OutSystems requires a case-insensitive SQL Server collation."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 14
    error_message = "Backup retention not applied."
  }
}

run "non_prod_database_can_be_torn_down" {
  command = apply
  module {
    source = "./modules/database"
  }

  variables {
    multi_az                     = false
    deletion_protection          = false
    skip_final_snapshot          = true
    performance_insights_enabled = false
    enhanced_monitoring_interval = 0
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == null
    error_message = "No final snapshot identifier expected when skip_final_snapshot is true."
  }

  assert {
    condition     = length(aws_iam_role.enhanced_monitoring) == 0 && aws_db_instance.this.monitoring_interval == 0
    error_message = "Enhanced monitoring role must not be created when monitoring is disabled."
  }
}

run "rejects_unsupported_sql_edition" {
  command = plan
  module {
    source = "./modules/database"
  }

  variables {
    engine = "sqlserver-ex"
  }

  expect_failures = [var.engine]
}

run "rejects_invalid_backup_retention" {
  command = plan
  module {
    source = "./modules/database"
  }

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "requires_two_subnets" {
  command = plan
  module {
    source = "./modules/database"
  }

  variables {
    subnet_ids = ["subnet-aaaa"]
  }

  expect_failures = [var.subnet_ids]
}
