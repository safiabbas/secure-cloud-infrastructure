resource "aws_db_subnet_group" "main" {
  name = "secure-cloud-db-subnet-group"

  subnet_ids = [
    aws_subnet.data_a.id,
    aws_subnet.data_b.id,
  ]

  tags = {
    Name = "secure-cloud-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  count = var.enable_runtime_resources ? 1 : 0

  identifier = "secure-cloud-postgres"

  engine         = "postgres"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"

  manage_master_user_password = true

  db_subnet_group_name = aws_db_subnet_group.main.name

  vpc_security_group_ids = [
    aws_security_group.data.id
  ]

  parameter_group_name            = aws_db_parameter_group.postgres.name
  enabled_cloudwatch_logs_exports = ["postgresql"]

  publicly_accessible = false

  multi_az = false

  backup_retention_period = 7

  copy_tags_to_snapshot = true

  skip_final_snapshot = true

  tags = {
    Name = "secure-cloud-postgres"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "secure-cloud-postgres-params"
  family = "postgres18"

  parameter {
    name  = "log_connections"
    value = "authentication,authorization"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "secure-cloud-postgres-params"
  }
}