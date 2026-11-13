# Shared mock data for the mocked AWS provider used by all offline tests.
# The AWS provider still validates ARN formats, so every resource whose ARN
# is consumed by another resource gets a realistic fake ARN here.

mock_resource "aws_kms_key" {
  defaults = {
    arn    = "arn:aws:kms:ap-southeast-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    key_id = "00000000-0000-0000-0000-000000000000"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::123456789012:role/mock-role"
  }
}

mock_resource "aws_iam_instance_profile" {
  defaults = {
    arn = "arn:aws:iam::123456789012:instance-profile/mock-profile"
  }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = {
    arn = "arn:aws:logs:ap-southeast-1:123456789012:log-group:mock"
  }
}

mock_resource "aws_s3_bucket" {
  defaults = {
    arn = "arn:aws:s3:::mock-bucket"
  }
}

mock_resource "aws_lb" {
  defaults = {
    arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:123456789012:loadbalancer/app/mock-alb/0123456789abcdef"
    arn_suffix = "app/mock-alb/0123456789abcdef"
    dns_name   = "mock-alb-123456789.ap-southeast-1.elb.amazonaws.com"
  }
}

mock_resource "aws_lb_target_group" {
  defaults = {
    arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:123456789012:targetgroup/mock-tg/0123456789abcdef"
    arn_suffix = "targetgroup/mock-tg/0123456789abcdef"
  }
}

mock_resource "aws_lb_listener" {
  defaults = {
    arn = "arn:aws:elasticloadbalancing:ap-southeast-1:123456789012:listener/app/mock-alb/0123456789abcdef/0123456789abcdef"
  }
}

mock_resource "aws_wafv2_web_acl" {
  defaults = {
    arn = "arn:aws:wafv2:ap-southeast-1:123456789012:regional/webacl/mock/00000000-0000-0000-0000-000000000000"
  }
}

mock_resource "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:ap-southeast-1:123456789012:mock-alarms"
  }
}

mock_resource "aws_instance" {
  defaults = {
    id         = "i-0123456789abcdef0"
    private_ip = "10.0.10.10"
  }
}

mock_resource "aws_launch_template" {
  defaults = {
    id             = "lt-0123456789abcdef0"
    latest_version = 1
  }
}

mock_resource "aws_db_instance" {
  defaults = {
    address = "mock-sqlserver.abcdefghij.ap-southeast-1.rds.amazonaws.com"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-mock"
      secret_status = "active"
      kms_key_id    = "arn:aws:kms:ap-southeast-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }]
  }
}

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition = "aws"
  }
}

mock_data "aws_ssm_parameter" {
  defaults = {
    value = "ami-0123456789abcdef0"
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}
