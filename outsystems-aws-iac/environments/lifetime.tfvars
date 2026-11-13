# Dedicated LifeTime environment (manages Dev/Test/Prod). Single server farm.
environment         = "lifetime"
vpc_cidr            = "10.40.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b"]
single_nat_gateway  = true
acm_certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/REPLACE-ME-lifetime"

# Corporate VPN range allowed to open the LifeTime console
management_cidr_blocks = ["198.51.100.0/24"]
health_check_path      = "/LifeTime/"
outsystems_modules     = {} # LifeTime hosts no business apps

controller_instance_type  = "m6i.large"
frontend_instance_type    = "m6i.large"
frontend_min_size         = 1
frontend_desired_capacity = 1
frontend_max_size         = 1

db_instance_class        = "db.m6i.large"
db_allocated_storage     = 50
db_max_allocated_storage = 200
db_multi_az              = false
db_backup_retention_days = 14

enable_waf         = true
log_retention_days = 90
