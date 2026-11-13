# Unit tests for modules/storage and modules/monitoring.
mock_provider "aws" {
  source = "./tests/mocks"
}

run "artifact_bucket_is_private_encrypted_and_versioned" {
  command = apply
  module {
    source = "./modules/storage"
  }

  variables {
    name_prefix        = "hi-unit"
    account_id         = "123456789012"
    kms_key_arn        = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
    log_retention_days = 90
    force_destroy      = false
  }

  assert {
    condition = alltrue([
      for b in [aws_s3_bucket_public_access_block.artifacts, aws_s3_bucket_public_access_block.logs] :
      b.block_public_acls && b.block_public_policy && b.ignore_public_acls && b.restrict_public_buckets
    ])
    error_message = "All buckets must block every form of public access."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.artifacts.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Artifacts bucket must use SSE-KMS."
  }

  assert {
    condition     = aws_s3_bucket_versioning.artifacts.versioning_configuration[0].status == "Enabled"
    error_message = "Artifacts bucket must be versioned."
  }

  assert {
    condition = alltrue([
      for p in [aws_s3_bucket_policy.artifacts.policy, aws_s3_bucket_policy.logs.policy] :
      strcontains(p, "aws:SecureTransport")
    ])
    error_message = "Bucket policies must deny non-TLS access."
  }

  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "hi-unit-artifacts-123456789012" && aws_s3_bucket.artifacts.force_destroy == false
    error_message = "Bucket naming/force_destroy not as expected."
  }
}

run "alarms_cover_edge_compute_and_database" {
  command = apply
  module {
    source = "./modules/monitoring"
  }

  variables {
    name_prefix             = "hi-unit"
    kms_key_arn             = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
    alarm_email             = "ops@example.com"
    log_group_prefix        = "/outsystems/hi-unit"
    log_retention_days      = 90
    alb_arn_suffix          = "app/hi-unit-alb/abc"
    target_group_arn_suffix = "targetgroup/hi-unit-fe/def"
    frontend_asg_name       = "hi-unit-frontend"
    controller_instance_id  = "i-0123456789abcdef0"
    db_instance_identifier  = "hi-unit-sqlserver"
    db_allocated_storage_gb = 100
  }

  assert {
    condition = alltrue([
      for ns in ["AWS/ApplicationELB", "AWS/EC2", "AWS/RDS"] :
      anytrue([for a in values(aws_cloudwatch_metric_alarm.this) : a.namespace == ns])
    ])
    error_message = "Alarms must cover the ALB, the EC2 servers and RDS."
  }

  assert {
    condition     = alltrue([for a in values(aws_cloudwatch_metric_alarm.this) : contains(a.alarm_actions, aws_sns_topic.alarms.arn)])
    error_message = "Every alarm must notify the SNS topic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["db-free-storage"].threshold == 10737418240
    error_message = "Free-storage alarm must fire at 10% of allocated storage."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1 && aws_sns_topic.alarms.kms_master_key_id == var.kms_key_arn
    error_message = "Encrypted alarm topic with an e-mail subscription expected."
  }
}
