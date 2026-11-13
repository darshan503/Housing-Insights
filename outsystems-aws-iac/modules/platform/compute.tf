###############################################################################
# OutSystems servers (Windows Server 2022):
#   - 1 x Deployment Controller (fixed instance, also hosts Service Center)
#   - N x Front-ends in an Auto Scaling Group behind the ALB
###############################################################################
data "aws_ssm_parameter" "windows_2022" {
  count = var.ami_id == "" ? 1 : 0
  name  = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.windows_2022[0].value)

  bootstrap_common = {
    environment      = var.environment
    artifacts_bucket = var.artifacts_bucket_name
    installer_s3_key = var.platform_installer_s3_key
    db_endpoint      = var.db_endpoint
    log_group_prefix = var.log_group_prefix
  }
}

# --- Deployment Controller ---------------------------------------------------
resource "aws_instance" "controller" {
  ami                     = local.ami_id
  instance_type           = var.controller_instance_type
  subnet_id               = var.app_subnet_ids[0]
  vpc_security_group_ids  = [var.controller_security_group]
  iam_instance_profile    = aws_iam_instance_profile.instance.name
  monitoring              = true
  disable_api_termination = var.is_production
  ebs_optimized           = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 150
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/bootstrap.ps1.tftpl", merge(local.bootstrap_common, {
    server_role   = "controller"
    controller_ip = ""
  }))

  tags = {
    Name           = "${var.name_prefix}-controller"
    OutSystemsRole = "DeploymentController"
    "Patch Group"  = "${var.name_prefix}-outsystems"
  }

  lifecycle {
    ignore_changes = [ami, user_data] # AMI updates are rolled out deliberately, not on every plan
  }
}

# --- Front-ends --------------------------------------------------------------
resource "aws_launch_template" "frontend" {
  name_prefix            = "${var.name_prefix}-frontend-"
  image_id               = local.ami_id
  instance_type          = var.frontend_instance_type
  vpc_security_group_ids = [var.frontend_security_group]
  ebs_optimized          = true
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = 100
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/bootstrap.ps1.tftpl", merge(local.bootstrap_common, {
    server_role   = "frontend"
    controller_ip = aws_instance.controller.private_ip
  })))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name           = "${var.name_prefix}-frontend"
      OutSystemsRole = "FrontEnd"
      "Patch Group"  = "${var.name_prefix}-outsystems"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name_prefix}-frontend" }
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.name_prefix}-frontend"
  vpc_zone_identifier       = var.app_subnet_ids
  min_size                  = var.frontend_min_size
  max_size                  = var.frontend_max_size
  desired_capacity          = var.frontend_desired_capacity
  target_group_arns         = [aws_lb_target_group.frontend.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 1800 # Windows boot + Platform Server install/registration
  default_instance_warmup   = 600
  enabled_metrics           = ["GroupInServiceInstances", "GroupDesiredCapacity", "GroupTotalInstances"]

  launch_template {
    id      = aws_launch_template.frontend.id
    version = aws_launch_template.frontend.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-frontend"
    propagate_at_launch = true
  }

  lifecycle {
    precondition {
      condition     = var.frontend_min_size <= var.frontend_desired_capacity && var.frontend_desired_capacity <= var.frontend_max_size
      error_message = "Front-end sizes must satisfy min <= desired <= max."
    }
  }
}

resource "aws_autoscaling_policy" "frontend_cpu" {
  name                   = "${var.name_prefix}-frontend-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = 60
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
