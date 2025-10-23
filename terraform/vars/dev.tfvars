environment = "dev"

rds_defaults = {
  allocated_storage     = "30"
  max_allocated_storage = "50"
  engine                = "postgres"
  engine_version        = "14.15"
  instance_class        = "db.t3.micro"
  username              = "postgres"
}