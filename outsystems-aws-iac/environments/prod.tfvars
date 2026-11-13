environment         = "prod"
vpc_cidr            = "10.30.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
single_nat_gateway  = false # one NAT per AZ
acm_certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/REPLACE-ME-prod"

# LifeTime environment egress IPs, so LifeTime can manage this environment
management_cidr_blocks = ["203.0.113.10/32"]

controller_instance_type  = "m6i.xlarge"
frontend_instance_type    = "m6i.xlarge"
frontend_min_size         = 2
frontend_desired_capacity = 3
frontend_max_size         = 6

db_instance_class        = "db.m6i.xlarge"
db_allocated_storage     = 200
db_max_allocated_storage = 1000
db_multi_az              = true
db_backup_retention_days = 30

enable_waf         = true
alarm_email        = "ops@example.com"
log_retention_days = 365
