environment         = "dev"
vpc_cidr            = "10.10.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b"]
single_nat_gateway  = true
acm_certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/REPLACE-ME-dev"

controller_instance_type  = "t3.xlarge"
frontend_instance_type    = "t3.large"
frontend_min_size         = 1
frontend_desired_capacity = 1
frontend_max_size         = 2

db_instance_class               = "db.t3.xlarge"
db_allocated_storage            = 50
db_max_allocated_storage        = 200
db_multi_az                     = false
db_backup_retention_days        = 7
db_performance_insights_enabled = false

enable_waf         = false
log_retention_days = 30
