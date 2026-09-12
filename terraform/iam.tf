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

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:safiabbas/secure-cloud-infrastructure:ref:refs/heads/main"
      ]
    }
  }
}

data "aws_iam_policy_document" "github_actions_security_scan" {
  statement {
    sid    = "ReadEC2SecurityConfiguration"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeFlowLogs"
    ]

    resources = ["*"]

    #checkov:skip=CKV_AWS_356:Account-wide read-only security scanner requires wildcard resource scope for AWS list and describe APIs; role contains no create, modify, or delete permissions.
  }

  statement {
    sid    = "ReadS3SecurityConfiguration"
    effect = "Allow"

    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadCloudTrailConfiguration"
    effect = "Allow"

    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadSecretsMetadata"
    effect = "Allow"

    actions = [
      "secretsmanager:ListSecrets",
      "secretsmanager:DescribeSecret"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadCallerIdentity"
    effect = "Allow"

    actions = [
      "sts:GetCallerIdentity"
    ]

    resources = ["*"]
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

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

resource "aws_iam_role" "github_actions_security_scan" {
  name               = "secure-cloud-github-actions-security-scan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name    = "secure-cloud-github-actions-security-scan"
    Purpose = "GitHub Actions security scanning"
  }
}

resource "aws_iam_role_policy" "github_actions_security_scan" {
  name   = "secure-cloud-github-actions-security-scan-policy"
  role   = aws_iam_role.github_actions_security_scan.id
  policy = data.aws_iam_policy_document.github_actions_security_scan.json
}