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

resource "aws_s3_bucket" "app" {
  bucket = "secure-cloud-app-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "secure-cloud-app-storage"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }

  #checkov:skip=CKV2_AWS_62:No event-driven workflow consumes bucket notifications in this lab
  #checkov:skip=CKV_AWS_18:Dedicated S3 server access logging is outside current lab scope
  #checkov:skip=CKV_AWS_144:Cross-region replication omitted for lab cost and scope
  #checkov:skip=CKV_AWS_145:SSE-S3 encryption is enabled; customer-managed KMS is intentionally outside lab scope
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

resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}