# REAL-AWS integration test. Creates a small dev stack, verifies it with
# live AWS API calls and HTTP requests, then destroys it automatically.
#
# Costs money (~1 hour of RDS + EC2 + NAT). Requires AWS credentials and a
# real ACM certificate in the target region:
#   terraform test -test-directory=tests/integration \
#     -var="acm_certificate_arn=arn:aws:acm:ap-southeast-1:<acct>:certificate/<id>"

variables {
  project_name                    = "hiinttest"
  environment                     = "dev"
  vpc_cidr                        = "10.99.0.0/16"
  availability_zones              = ["ap-southeast-1a", "ap-southeast-1b"]
  single_nat_gateway              = true
  controller_instance_type        = "t3.large"
  frontend_instance_type          = "t3.large"
  frontend_min_size               = 1
  frontend_desired_capacity       = 1
  frontend_max_size               = 1
  db_instance_class               = "db.t3.xlarge"
  db_allocated_storage            = 20
  db_max_allocated_storage        = 50
  db_multi_az                     = false
  db_backup_retention_days        = 1
  db_performance_insights_enabled = false
  enable_waf                      = true
  log_retention_days              = 1
}

run "deploy" {
  command = apply

  assert {
    condition     = endswith(output.alb_dns_name, ".elb.amazonaws.com")
    error_message = "ALB was not created with a public DNS name."
  }
}

run "verify_live_infrastructure" {
  command = apply

  module {
    source = "./tests/integration/verify"
  }

  variables {
    name_prefix  = "hiinttest-dev"
    alb_dns_name = run.deploy.alb_dns_name
  }

  assert {
    condition     = data.aws_db_instance.this.storage_encrypted && !data.aws_db_instance.this.publicly_accessible
    error_message = "Live RDS instance is not encrypted or is publicly accessible."
  }

  assert {
    condition     = data.aws_db_instance.this.db_instance_status == "available"
    error_message = "Live RDS instance is not available."
  }

  assert {
    condition     = data.aws_lb.this.internal == false && data.aws_lb.this.drop_invalid_header_fields
    error_message = "Live ALB configuration differs from the expected hardened configuration."
  }

  assert {
    condition     = data.aws_autoscaling_group.frontend.desired_capacity == 1
    error_message = "Front-end ASG not at desired capacity."
  }

  assert {
    condition     = data.http.service_center.status_code == 403
    error_message = "/ServiceCenter must return 403 to the public internet."
  }
}
