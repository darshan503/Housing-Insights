# Helper module used only by tests/integration: reads back the live resources.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

variable "name_prefix" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

data "aws_db_instance" "this" {
  db_instance_identifier = "${var.name_prefix}-sqlserver"
}

data "aws_lb" "this" {
  name = "${var.name_prefix}-alb"
}

data "aws_autoscaling_group" "frontend" {
  name = "${var.name_prefix}-frontend"
}

# The ACM cert will not match the raw ALB host name, hence insecure = true.
data "http" "service_center" {
  url      = "https://${var.alb_dns_name}/ServiceCenter/"
  insecure = true
}
