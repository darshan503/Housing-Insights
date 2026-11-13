###############################################################################
# Public Application Load Balancer in front of the OutSystems front-ends.
###############################################################################
resource "aws_lb" "this" {
  name                       = "${var.name_prefix}-alb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [var.alb_security_group_id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.is_production
  idle_timeout               = 120

  access_logs {
    bucket  = var.logs_bucket_name
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${var.name_prefix}-fe"
  vpc_id               = var.vpc_id
  port                 = 443
  protocol             = "HTTPS" # re-encrypt ALB -> IIS
  target_type          = "instance"
  deregistration_delay = 60

  health_check {
    path                = var.health_check_path
    protocol            = "HTTPS"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Required for Traditional Web apps; harmless for Reactive apps.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# --- Platform management consoles are not exposed to the internet ----------
locals {
  management_paths = ["/ServiceCenter*", "/LifeTime*"]
}

# Trusted networks (e.g. the LifeTime environment's NAT IPs) may reach them...
resource "aws_lb_listener_rule" "management_allow" {
  count = length(var.management_cidr_blocks) > 0 ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    path_pattern {
      values = local.management_paths
    }
  }

  condition {
    source_ip {
      values = var.management_cidr_blocks
    }
  }
}

# ...everyone else is refused.
resource "aws_lb_listener_rule" "management_deny" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = local.management_paths
    }
  }
}
