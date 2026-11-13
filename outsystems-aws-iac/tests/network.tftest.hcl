# Unit tests for modules/network. Runs fully offline against a mocked AWS provider.
mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name_prefix             = "hi-unit"
  aws_region              = "ap-southeast-1"
  vpc_cidr                = "10.20.0.0/16"
  availability_zones      = ["ap-southeast-1a", "ap-southeast-1b"]
  single_nat_gateway      = true
  flow_log_retention_days = 30
  kms_key_arn             = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
}

run "creates_three_subnet_tiers_per_az" {
  command = apply
  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.data) == 2
    error_message = "Expected one public, one app and one data subnet per AZ."
  }

  assert {
    condition = (
      aws_subnet.public[0].cidr_block == "10.20.0.0/24" &&
      aws_subnet.app[0].cidr_block == "10.20.10.0/24" &&
      aws_subnet.data[1].cidr_block == "10.20.21.0/24"
    )
    error_message = "Subnet CIDR layout does not follow the public=0.., app=10.., data=20.. convention."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames && aws_vpc.this.enable_dns_support
    error_message = "DNS support/hostnames must be enabled (needed for RDS endpoint resolution)."
  }
}

run "single_nat_gateway_for_non_prod" {
  command = apply
  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_route_table.app) == 1
    error_message = "single_nat_gateway=true must create exactly one NAT gateway and app route table."
  }
}

run "nat_gateway_per_az_for_high_availability" {
  command = apply
  module {
    source = "./modules/network"
  }

  variables {
    single_nat_gateway = false
    availability_zones = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Expected one NAT gateway per AZ."
  }

  assert {
    condition     = alltrue([for i, a in aws_route_table_association.app : a.route_table_id == aws_route_table.app[i].id])
    error_message = "Each app subnet must route through the NAT gateway in its own AZ."
  }
}

run "data_tier_has_no_internet_route" {
  command = apply
  module {
    source = "./modules/network"
  }

  assert {
    condition = (
      alltrue([for r in aws_route.app_nat : r.route_table_id != aws_route_table.data.id]) &&
      aws_route.public_internet.route_table_id != aws_route_table.data.id
    )
    error_message = "The database tier must not have a default route to the internet."
  }

  assert {
    condition     = alltrue([for a in aws_route_table_association.data : a.route_table_id == aws_route_table.data.id])
    error_message = "All data subnets must use the isolated data route table."
  }
}

run "flow_logs_capture_all_traffic_encrypted" {
  command = apply
  module {
    source = "./modules/network"
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "VPC flow logs must capture ALL traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.kms_key_id == var.kms_key_arn
    error_message = "Flow log group must be KMS-encrypted."
  }
}
