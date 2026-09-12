resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-default-sg"
  }
}

resource "aws_security_group" "alb" {
  name        = "secure-cloud-public-sg"
  description = "Security group for public-facing resources"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-public-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443

  description = "Allow HTTPS from the internet"
}

resource "aws_security_group" "app" {
  name        = "secure-cloud-app-sg"
  description = "Security group for application resources"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id

  from_port   = 8080
  ip_protocol = "tcp"
  to_port     = 8080

  description = "Allow application traffic from public tier"
}

resource "aws_security_group" "data" {
  name        = "secure-cloud-data-sg"
  description = "Security group for database resources"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-data-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "data_from_app" {
  security_group_id = aws_security_group.data.id

  referenced_security_group_id = aws_security_group.app.id

  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432

  description = "Allow PostgreSQL traffic from application tier"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = aws_security_group.app.id

  from_port   = 8080
  ip_protocol = "tcp"
  to_port     = 8080

  description = "Allow application traffic to application tier"
}

resource "aws_vpc_security_group_egress_rule" "app_to_data" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.data.id

  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432

  description = "Allow PostgreSQL traffic to data tier"
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "secure-cloud-vpc-endpoints-sg"
  description = "Controls HTTPS access to interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-vpc-endpoints-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https_from_app" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = aws_security_group.app.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  description = "Allow HTTPS from app tier to interface VPC endpoints"
}

resource "aws_vpc_security_group_egress_rule" "app_https_to_vpc_endpoints" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  description = "Allow HTTPS from app tier to interface VPC endpoints"
}

resource "aws_vpc_security_group_egress_rule" "app_https_to_s3" {
  security_group_id = aws_security_group.app.id
  prefix_list_id    = data.aws_prefix_list.s3.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  description = "Allow HTTPS from app tier to Amazon S3"
}