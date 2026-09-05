data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "s3_require_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:*"
    ]

    resources = [
      aws_s3_bucket.app.arn,
      "${aws_s3_bucket.app.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.app.arn
    ]
  }

  statement {
    sid    = "ReadApplicationObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.app.arn}/*"
    ]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "secure-cloud-vpc"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "secure-cloud-public-subnet"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "secure-cloud-app-subnet"
    Tier = "application"
  }
}

resource "aws_subnet" "data" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "secure-cloud-data-subnet"
    Tier = "data"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "secure-cloud-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "public" {
  name        = "secure-cloud-public-sg"
  description = "Security group for public-facing resources"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-public-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_https" {
  security_group_id = aws_security_group.public.id

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

resource "aws_vpc_security_group_ingress_rule" "app_from_public" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.public.id

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

resource "aws_vpc_security_group_egress_rule" "public_to_app" {
  security_group_id = aws_security_group.public.id

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

resource "aws_eip" "nat" {
  count = var.enable_runtime_resources ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "secure-cloud-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.enable_runtime_resources ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "secure-cloud-nat-gateway"
  }
}

resource "aws_route_table" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = {
    Name = "secure-cloud-app-rt"
  }
}

resource "aws_route_table_association" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app[0].id
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  count = var.enable_runtime_resources ? 1 : 0

  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443

  description = "Allow outbound HTTPS for AWS services and updates"
}

resource "aws_iam_role" "ec2_ssm" {
  name = "secure-cloud-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "secure-cloud-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "secure-cloud-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.app.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "secure-cloud-app-instance"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }
}

resource "aws_s3_bucket" "app" {
  bucket = "secure-cloud-app-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "secure-cloud-app-storage"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.s3_require_tls.json
}

resource "aws_secretsmanager_secret" "app" {
  name        = "secure-cloud/app/database"
  description = "Application database credentials for the secure cloud lab"

  tags = {
    Name        = "secure-cloud-app-database-secret"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }
}

resource "aws_iam_policy" "app_permissions" {
  name        = "secure-cloud-app-permissions"
  description = "Least-privilege permissions for the application workload"

  policy = data.aws_iam_policy_document.app_permissions.json

  tags = {
    Name = "secure-cloud-app-permissions"
  }
}

resource "aws_iam_role_policy_attachment" "app_permissions" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = aws_iam_policy.app_permissions.arn
}