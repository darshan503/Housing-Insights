# Unit tests for modules/security - enforces the OutSystems network model.
mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name_prefix = "hi-unit"
  vpc_id      = "vpc-0123456789abcdef0"
}

run "only_alb_is_reachable_from_internet_on_web_ports" {
  command = apply
  module {
    source = "./modules/security"
  }

  assert {
    condition = alltrue([
      for r in values(aws_vpc_security_group_ingress_rule.this) :
      r.cidr_ipv4 == null || (r.security_group_id == aws_security_group.alb.id && contains([80, 443], r.from_port))
    ])
    error_message = "Only the ALB may accept traffic from CIDR ranges, and only on ports 80/443."
  }
}

run "no_remote_admin_ports_open" {
  command = apply
  module {
    source = "./modules/security"
  }

  assert {
    condition = !anytrue([
      for r in values(aws_vpc_security_group_ingress_rule.this) :
      contains([22, 3389, 5985, 5986], r.from_port)
    ])
    error_message = "SSH/RDP/WinRM must not be opened - use SSM Session Manager."
  }
}

run "database_only_accepts_sql_from_platform_servers" {
  command = apply
  module {
    source = "./modules/security"
  }

  assert {
    condition = alltrue([
      for r in values(aws_vpc_security_group_ingress_rule.this) :
      r.from_port == 1433 && r.cidr_ipv4 == null && contains([aws_security_group.frontend.id, aws_security_group.controller.id], r.referenced_security_group_id)
      if r.security_group_id == aws_security_group.database.id
    ])
    error_message = "Database SG must only allow 1433 from front-end and controller SGs."
  }

  assert {
    condition     = length([for r in values(aws_vpc_security_group_egress_rule.this) : r if r.security_group_id == aws_security_group.database.id]) == 0
    error_message = "Database SG must have no egress rules."
  }
}

run "outsystems_platform_ports_are_wired" {
  command = apply
  module {
    source = "./modules/security"
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.this["controller_deployctl_from_fe"].from_port == 12000 &&
      aws_vpc_security_group_ingress_rule.this["controller_deployctl_from_fe"].referenced_security_group_id == aws_security_group.frontend.id
    )
    error_message = "Front-ends must reach the Deployment Controller Service on 12000."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.this["controller_rabbitmq_from_fe"].from_port == 5672 &&
      aws_vpc_security_group_ingress_rule.this["frontend_deploysvc_from_ctl"].from_port == 12001 &&
      aws_vpc_security_group_ingress_rule.this["frontend_deploysvc_from_ctl"].referenced_security_group_id == aws_security_group.controller.id
    )
    error_message = "Cache invalidation (5672) and Deployment Service (12001) rules are missing or mis-wired."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.this["frontend_https_from_alb"].referenced_security_group_id == aws_security_group.alb.id &&
      aws_vpc_security_group_egress_rule.this["alb_to_frontend"].referenced_security_group_id == aws_security_group.frontend.id
    )
    error_message = "ALB <-> front-end HTTPS path is not correctly restricted."
  }
}
