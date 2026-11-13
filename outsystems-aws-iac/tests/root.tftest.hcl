# Integration-style tests of the ROOT module (all modules wired together),
# still offline with a mocked provider, plus input-validation tests.
mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  environment         = "prod"
  vpc_cidr            = "10.30.0.0/16"
  availability_zones  = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  single_nat_gateway  = false
  acm_certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/mock"
}

run "full_stack_wires_together" {
  command = apply

  assert {
    condition     = startswith(output.environment_url, "https://")
    error_message = "Environment URL must be HTTPS."
  }

  assert {
    condition     = output.artifacts_bucket == "housinginsights-prod-artifacts-123456789012"
    error_message = "Artifacts bucket name must follow <project>-<env>-artifacts-<account>."
  }

  assert {
    condition     = strcontains(output.service_center_tunnel_command, output.controller_instance_id)
    error_message = "SSM tunnel command must target the controller."
  }

  assert {
    condition     = output.frontend_asg_name == "housinginsights-prod-frontend"
    error_message = "Unexpected ASG name."
  }

  assert {
    condition = (
      length(output.application_urls) == 1 &&
      endswith(output.application_urls["SingaporeHousingInsights"], "/SingaporeHousingInsights/")
    )
    error_message = "Only the end-user module (SingaporeHousingInsights) should be exposed as an application URL."
  }

  assert {
    condition = (
      output.outsystems_modules["HousingInsights_core"] == "core" &&
      output.outsystems_modules["HousingInsights_integration"] == "integration"
    )
    error_message = "All three OutSystems modules must be registered with the correct layer."
  }

  assert {
    condition     = aws_kms_key.platform.enable_key_rotation
    error_message = "KMS key rotation must be enabled."
  }
}

# ---------------------------------------------------------------- validation
run "rejects_unknown_environment" {
  command = plan
  variables {
    environment = "staging"
  }
  expect_failures = [var.environment]
}

run "rejects_invalid_project_name" {
  command = plan
  variables {
    project_name = "Housing_Insights"
  }
  expect_failures = [var.project_name]
}

run "rejects_single_availability_zone" {
  command = plan
  variables {
    availability_zones = ["ap-southeast-1a"]
  }
  expect_failures = [var.availability_zones]
}

run "rejects_world_open_management_access" {
  command = plan
  variables {
    management_cidr_blocks = ["0.0.0.0/0"]
  }
  expect_failures = [var.management_cidr_blocks]
}

run "rejects_malformed_certificate_arn" {
  command = plan
  variables {
    acm_certificate_arn = "not-an-arn"
  }
  expect_failures = [var.acm_certificate_arn]
}

run "rejects_express_edition" {
  command = plan
  variables {
    db_engine = "sqlserver-ex"
  }
  expect_failures = [var.db_engine]
}

run "rejects_unknown_module_layer" {
  command = plan
  variables {
    outsystems_modules = {
      Foo = { layer = "ui", description = "bad layer", expose_url = true }
    }
  }
  expect_failures = [var.outsystems_modules]
}

run "rejects_invalid_vpc_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.30.0.0/28"
  }
  expect_failures = [var.vpc_cidr]
}
