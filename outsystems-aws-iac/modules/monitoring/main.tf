###############################################################################
# Operational monitoring: alarm topic, log groups, and alarms covering the
# edge (ALB), the OutSystems servers and the database.
###############################################################################
resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_log_group" "server" {
  for_each = toset(["iis", "windows-events"])

  name              = "${var.log_group_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

locals {
  actions = [aws_sns_topic.alarms.arn]

  alarms = {
    alb-5xx = {
      description = "ALB is returning 5xx errors (no healthy targets / LB errors)."
      namespace   = "AWS/ApplicationELB"
      metric      = "HTTPCode_ELB_5XX_Count"
      statistic   = "Sum"
      threshold   = 10
      operator    = "GreaterThanThreshold"
      periods     = 1
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
    target-5xx = {
      description = "OutSystems front-ends are returning 5xx errors."
      namespace   = "AWS/ApplicationELB"
      metric      = "HTTPCode_Target_5XX_Count"
      statistic   = "Sum"
      threshold   = 25
      operator    = "GreaterThanThreshold"
      periods     = 2
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
    unhealthy-frontends = {
      description = "At least one OutSystems front-end is failing health checks."
      namespace   = "AWS/ApplicationELB"
      metric      = "UnHealthyHostCount"
      statistic   = "Maximum"
      threshold   = 0
      operator    = "GreaterThanThreshold"
      periods     = 3
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
    slow-responses = {
      description = "Average front-end response time above 3 seconds."
      namespace   = "AWS/ApplicationELB"
      metric      = "TargetResponseTime"
      statistic   = "Average"
      threshold   = 3
      operator    = "GreaterThanThreshold"
      periods     = 3
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
    frontend-cpu = {
      description = "Front-end CPU saturated even after scaling."
      namespace   = "AWS/EC2"
      metric      = "CPUUtilization"
      statistic   = "Average"
      threshold   = 85
      operator    = "GreaterThanThreshold"
      periods     = 3
      dimensions  = { AutoScalingGroupName = var.frontend_asg_name }
    }
    controller-status = {
      description = "Deployment Controller failed an EC2 status check."
      namespace   = "AWS/EC2"
      metric      = "StatusCheckFailed"
      statistic   = "Maximum"
      threshold   = 0
      operator    = "GreaterThanThreshold"
      periods     = 2
      dimensions  = { InstanceId = var.controller_instance_id }
    }
    db-cpu = {
      description = "RDS SQL Server CPU above 80%."
      namespace   = "AWS/RDS"
      metric      = "CPUUtilization"
      statistic   = "Average"
      threshold   = 80
      operator    = "GreaterThanThreshold"
      periods     = 3
      dimensions  = { DBInstanceIdentifier = var.db_instance_identifier }
    }
    db-free-storage = {
      description = "RDS free storage below 10% of allocated storage."
      namespace   = "AWS/RDS"
      metric      = "FreeStorageSpace"
      statistic   = "Minimum"
      threshold   = var.db_allocated_storage_gb * 1073741824 * 0.10
      operator    = "LessThanThreshold"
      periods     = 1
      dimensions  = { DBInstanceIdentifier = var.db_instance_identifier }
    }
    db-free-memory = {
      description = "RDS freeable memory below 512 MiB."
      namespace   = "AWS/RDS"
      metric      = "FreeableMemory"
      statistic   = "Average"
      threshold   = 536870912
      operator    = "LessThanThreshold"
      periods     = 3
      dimensions  = { DBInstanceIdentifier = var.db_instance_identifier }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  comparison_operator = each.value.operator
  evaluation_periods  = each.value.periods
  period              = 300
  dimensions          = each.value.dimensions
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}
