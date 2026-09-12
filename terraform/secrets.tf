resource "aws_secretsmanager_secret" "app" {
  name        = "secure-cloud/app/database"
  description = "Application database credentials for the secure cloud lab"

  tags = {
    Name        = "secure-cloud-app-database-secret"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }

  #checkov:skip=CKV_AWS_149:Legacy lab secret uses AWS-managed Secrets Manager encryption; customer-managed KMS is outside lab scope
  #checkov:skip=CKV2_AWS_57:Legacy secret is not used for RDS master authentication; automatic rotation is outside current lab scope
}
