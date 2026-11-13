# Unit tests for modules/platform (ALB, WAF, controller, front-end ASG, IAM).
mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name_prefix               = "hi-unit"
  environment               = "prod"
  is_production             = true
  vpc_id                    = "vpc-0123456789abcdef0"
  public_subnet_ids         = ["subnet-pub-a", "subnet-pub-b"]
  app_subnet_ids            = ["subnet-app-a", "subnet-app-b"]
  alb_security_group_id     = "sg-alb"
  frontend_security_group   = "sg-fe"
  controller_security_group = "sg-ctl"
  acm_certificate_arn       = "arn:aws:acm:ap-southeast-1:123456789012:certificate/mock"
  health_check_path         = "/SingaporeHousingInsights/"
  management_cidr_blocks    = []
  enable_waf                = true
  waf_rate_limit            = 2000
  ami_id                    = ""
  controller_instance_type  = "m6i.xlarge"
  frontend_instance_type    = "m6i.xlarge"
  frontend_min_size         = 2
  frontend_max_size         = 4
  frontend_desired_capacity = 2
  kms_key_arn               = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
  artifacts_bucket_name     = "hi-unit-artifacts"
  artifacts_bucket_arn      = "arn:aws:s3:::hi-unit-artifacts"
  logs_bucket_name          = "hi-unit-logs"
  platform_installer_s3_key = ""
  db_endpoint               = "hi-unit-sqlserver.abc.ap-southeast-1.rds.amazonaws.com"
  db_secret_arn             = null
  log_group_prefix          = "/outsystems/hi-unit"
}

run "alb_enforces_https" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition = (
      aws_lb_listener.http.default_action[0].type == "redirect" &&
      aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" &&
      aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301"
    )
    error_message = "HTTP listener must permanently redirect to HTTPS."
  }

  assert {
    condition     = startswith(aws_lb_listener.https.ssl_policy, "ELBSecurityPolicy-TLS13")
    error_message = "HTTPS listener must use a TLS 1.2/1.3 security policy."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.access_logs[0].enabled
    error_message = "ALB must drop invalid headers and write access logs."
  }

  assert {
    condition     = aws_lb_target_group.frontend.protocol == "HTTPS" && aws_lb_target_group.frontend.health_check[0].path == "/SingaporeHousingInsights/"
    error_message = "Target group must re-encrypt to the front-ends and use the configured health check."
  }
}

run "management_consoles_blocked_from_internet" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition = (
      aws_lb_listener_rule.management_deny.action[0].fixed_response[0].status_code == "403" &&
      anytrue([for c in aws_lb_listener_rule.management_deny.condition : contains(try(tolist(c.path_pattern[0].values), []), "/ServiceCenter*")])
    )
    error_message = "/ServiceCenter and /LifeTime must return 403 to the public."
  }

  assert {
    condition     = length(aws_lb_listener_rule.management_allow) == 0
    error_message = "No allow rule should exist when no management CIDRs are configured."
  }
}

run "management_consoles_allowed_for_trusted_cidrs" {
  command = apply
  module {
    source = "./modules/platform"
  }

  variables {
    management_cidr_blocks = ["203.0.113.10/32"]
  }

  assert {
    condition     = length(aws_lb_listener_rule.management_allow) == 1 && aws_lb_listener_rule.management_allow[0].priority < aws_lb_listener_rule.management_deny.priority
    error_message = "Trusted-CIDR allow rule must exist and be evaluated before the deny rule."
  }
}

run "servers_are_hardened" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition = (
      aws_launch_template.frontend.metadata_options[0].http_tokens == "required" &&
      aws_instance.controller.metadata_options[0].http_tokens == "required"
    )
    error_message = "IMDSv2 must be enforced on all OutSystems servers."
  }

  assert {
    condition = (
      tostring(aws_launch_template.frontend.block_device_mappings[0].ebs[0].encrypted) == "true" &&
      aws_instance.controller.root_block_device[0].encrypted
    )
    error_message = "All EBS volumes must be encrypted."
  }

  assert {
    condition     = aws_instance.controller.disable_api_termination == true
    error_message = "Production controller must have termination protection."
  }

  assert {
    condition     = aws_instance.controller.ami == "ami-0123456789abcdef0"
    error_message = "Controller should use the Windows Server 2022 AMI resolved from SSM."
  }
}

run "bootstrap_is_role_specific" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.frontend.user_data), "$Role            = 'frontend'") &&
      strcontains(base64decode(aws_launch_template.frontend.user_data), aws_instance.controller.private_ip)
    )
    error_message = "Front-end bootstrap must declare the frontend role and know the controller IP."
  }

  assert {
    condition     = strcontains(aws_instance.controller.user_data, "$Role            = 'controller'")
    error_message = "Controller bootstrap must declare the controller role."
  }
}

run "frontends_autoscale_behind_alb" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition = (
      aws_autoscaling_group.frontend.min_size == 2 &&
      aws_autoscaling_group.frontend.max_size == 4 &&
      aws_autoscaling_group.frontend.health_check_type == "ELB" &&
      contains(aws_autoscaling_group.frontend.target_group_arns, aws_lb_target_group.frontend.arn)
    )
    error_message = "Front-end ASG must be registered with the ALB and use ELB health checks."
  }

  assert {
    condition     = toset(aws_autoscaling_group.frontend.vpc_zone_identifier) == toset(var.app_subnet_ids)
    error_message = "Front-ends must run in the private app subnets."
  }
}

run "waf_attached_when_enabled" {
  command = apply
  module {
    source = "./modules/platform"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1 && aws_wafv2_web_acl_association.alb[0].resource_arn == aws_lb.this.arn
    error_message = "WAF web ACL must be created and associated with the ALB."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this[0].rule) == 4
    error_message = "Expected 3 managed rule groups + 1 rate-limit rule."
  }
}

run "waf_skipped_when_disabled" {
  command = apply
  module {
    source = "./modules/platform"
  }

  variables {
    enable_waf    = false
    is_production = false
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0 && length(aws_wafv2_web_acl_association.alb) == 0
    error_message = "No WAF resources expected when enable_waf=false."
  }

  assert {
    condition     = aws_instance.controller.disable_api_termination == false && aws_lb.this.enable_deletion_protection == false
    error_message = "Non-prod stacks must stay destroyable."
  }
}

run "iam_grants_secret_access_only_when_secret_exists" {
  command = apply
  module {
    source = "./modules/platform"
  }

  variables {
    db_secret_arn = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-mock"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.instance.policy).Statement) == 3
    error_message = "Instance policy should contain artifacts, KMS and secret statements."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.instance.policy, "\"*\"")
    error_message = "Instance policy must not use wildcard resources."
  }
}

run "rejects_inconsistent_asg_sizes" {
  command = plan
  module {
    source = "./modules/platform"
  }

  variables {
    frontend_min_size         = 3
    frontend_desired_capacity = 2
  }

  expect_failures = [aws_autoscaling_group.frontend]
}
