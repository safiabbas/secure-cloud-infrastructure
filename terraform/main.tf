locals {
  cloudtrail_name = "secure-cloud-trail"
  cloudtrail_arn  = "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

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

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.us-east-1.s3"
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*"
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowCloudTrailAclCheck"
    effect = "Allow"

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      aws_s3_bucket.cloudtrail.arn
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid    = "AllowCloudTrailWrite"
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
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

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-app-rt"
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "secure-cloud-data-rt"
  }
}

resource "aws_route_table_association" "data" {
  subnet_id      = aws_subnet.data.id
  route_table_id = aws_route_table.data.id
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

resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
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

  root_block_device {
    encrypted = true
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
}

resource "aws_vpc_security_group_egress_rule" "app_https_to_vpc_endpoints" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_runtime_resources ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "secure-cloud-secretsmanager-endpoint"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_https_to_s3" {
  security_group_id = aws_security_group.app.id
  prefix_list_id    = data.aws_prefix_list.s3.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  description = "Allow HTTPS from app tier to Amazon S3"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "secure-cloud-audit-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "secure-cloud-audit"
    Purpose = "CloudTrail audit logging"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-cloudtrail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}