###############################################################################
# Least-privilege security groups for the OutSystems farm.
#
# OutSystems 11 network requirements implemented here:
#   ALB          -> front-ends   443  (HTTPS, re-encrypted)
#   front-ends   -> controller   12000 (Deployment Controller Service)
#   front-ends   -> controller   5672  (Cache Invalidation Service / RabbitMQ)
#   controller   -> front-ends   12001 (Deployment Service)
#   front-ends + controller -> RDS 1433
# No RDP/WinRM is opened: administration happens through SSM Session Manager.
###############################################################################
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Public ALB for OutSystems front-ends"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-alb" }
}

resource "aws_security_group" "frontend" {
  name        = "${var.name_prefix}-frontend"
  description = "OutSystems front-end servers"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-frontend" }
}

resource "aws_security_group" "controller" {
  name        = "${var.name_prefix}-controller"
  description = "OutSystems Deployment Controller server"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-controller" }
}

resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-database"
  description = "RDS SQL Server for OutSystems"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-database" }
}

locals {
  sg_ids = {
    alb        = aws_security_group.alb.id
    frontend   = aws_security_group.frontend.id
    controller = aws_security_group.controller.id
    database   = aws_security_group.database.id
  }

  # Every rule has the same shape; exactly one of cidr / source is set.
  ingress_rules = {
    alb_https_internet           = { sg = "alb", port = 443, cidr = "0.0.0.0/0", source = null, description = "HTTPS from internet" }
    alb_http_internet            = { sg = "alb", port = 80, cidr = "0.0.0.0/0", source = null, description = "HTTP from internet (redirected to HTTPS)" }
    frontend_https_from_alb      = { sg = "frontend", port = 443, cidr = null, source = "alb", description = "HTTPS from ALB" }
    frontend_deploysvc_from_ctl  = { sg = "frontend", port = 12001, cidr = null, source = "controller", description = "OutSystems Deployment Service" }
    controller_deployctl_from_fe = { sg = "controller", port = 12000, cidr = null, source = "frontend", description = "OutSystems Deployment Controller Service" }
    controller_rabbitmq_from_fe  = { sg = "controller", port = 5672, cidr = null, source = "frontend", description = "OutSystems Cache Invalidation Service (RabbitMQ)" }
    database_sql_from_frontend   = { sg = "database", port = 1433, cidr = null, source = "frontend", description = "SQL Server from front-ends" }
    database_sql_from_ctl        = { sg = "database", port = 1433, cidr = null, source = "controller", description = "SQL Server from controller" }
  }

  egress_rules = {
    alb_to_frontend     = { sg = "alb", protocol = "tcp", port = 443, cidr = null, target = "frontend", description = "ALB to front-ends" }
    frontend_outbound   = { sg = "frontend", protocol = "-1", port = null, cidr = "0.0.0.0/0", target = null, description = "Outbound via NAT (data.gov.sg API, updates, licensing)" }
    controller_outbound = { sg = "controller", protocol = "-1", port = null, cidr = "0.0.0.0/0", target = null, description = "Outbound via NAT (updates, licensing)" }
    # database: no egress rules at all
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id            = local.sg_ids[each.value.sg]
  description                  = each.value.description
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.source == null ? null : local.sg_ids[each.value.source]
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.egress_rules

  security_group_id            = local.sg_ids[each.value.sg]
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.target == null ? null : local.sg_ids[each.value.target]
}
