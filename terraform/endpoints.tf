data "aws_prefix_list" "s3" {
  name = "com.amazonaws.us-east-1.s3"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.app.id
  ]

  tags = {
    Name = "secure-cloud-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
  ]

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
  ]

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
  ]

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-secretsmanager-endpoint"
  }
}