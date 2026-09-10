data "aws_iam_policy_document" "app_rds_secret_access" {
  count = var.enable_runtime_resources ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_db_instance.postgres[0].master_user_secret[0].secret_arn
    ]
  }
}

data "aws_iam_policy_document" "app_permissions" {
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

resource "aws_iam_role_policy" "app_rds_secret_access" {
  count = var.enable_runtime_resources ? 1 : 0

  name   = "secure-cloud-app-rds-secret-access"
  role   = aws_iam_role.ec2_ssm.id
  policy = data.aws_iam_policy_document.app_rds_secret_access[0].json
}