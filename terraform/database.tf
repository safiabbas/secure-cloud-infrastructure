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

  publicly_accessible = false

  multi_az = false

  backup_retention_period = 7

  skip_final_snapshot = true

  tags = {
    Name = "secure-cloud-postgres"
  }
}