output "alarm_topic_arn" {
  description = "SNS topic for alarms."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Names of all alarms created."
  value       = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]
}
