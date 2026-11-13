# Policy-as-code checks for each environment's tfvars file.
# Run once per environment, e.g.:
#   terraform test -test-directory=tests/policy -var-file=environments/prod.tfvars
mock_provider "aws" {
  source = "./tests/mocks"
}

run "environment_plans_successfully" {
  command = plan
}

run "certificate_is_in_deployment_region" {
  command = plan

  assert {
    condition     = strcontains(var.acm_certificate_arn, ":${var.aws_region}:")
    error_message = "The ACM certificate must live in the same region as the ALB."
  }
}

run "frontend_capacity_is_consistent" {
  command = plan

  assert {
    condition     = var.frontend_min_size <= var.frontend_desired_capacity && var.frontend_desired_capacity <= var.frontend_max_size
    error_message = "Front-end sizes must satisfy min <= desired <= max."
  }
}

run "all_three_outsystems_modules_are_hosted" {
  command = plan

  assert {
    condition = (
      var.environment == "lifetime" ||
      alltrue([for m in ["SingaporeHousingInsights", "HousingInsights_core", "HousingInsights_integration"] : contains(keys(var.outsystems_modules), m)])
    )
    error_message = "Application environments must host the UI, core and integration modules."
  }
}

run "production_is_highly_available" {
  command = plan

  assert {
    condition     = var.environment != "prod" || (var.db_multi_az && !var.single_nat_gateway && var.frontend_min_size >= 2)
    error_message = "Prod requires a Multi-AZ database, one NAT gateway per AZ and at least 2 front-ends."
  }

  assert {
    condition     = var.environment != "prod" || (var.enable_waf && var.alarm_email != "" && var.db_backup_retention_days >= 14)
    error_message = "Prod requires WAF, an alarm recipient and >= 14 days of DB backups."
  }
}

run "lifetime_reachable_only_from_trusted_networks" {
  command = plan

  assert {
    condition     = var.environment != "lifetime" || length(var.management_cidr_blocks) > 0
    error_message = "The LifeTime environment must declare management_cidr_blocks, otherwise the console is unreachable."
  }
}
