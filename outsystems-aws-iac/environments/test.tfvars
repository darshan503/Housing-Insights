environment         = "test"
vpc_cidr            = "10.20.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b"]
single_nat_gateway  = true
acm_certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/REPLACE-ME-test"

controller_instance_type  = "m6i.large"
frontend_instance_type    = "m6i.large"
frontend_min_size         = 2
frontend_desired_capacity = 2
frontend_max_size         = 3

db_instance_class        = "db.m6i.large"
db_allocated_storage     = 100
db_max_allocated_storage = 300
db_multi_az              = false
db_backup_retention_days = 7

enable_waf         = true
log_retention_days = 30
