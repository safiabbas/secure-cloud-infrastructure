resource "aws_secretsmanager_secret" "app" {
  name        = "secure-cloud/app/database"
  description = "Application database credentials for the secure cloud lab"

  tags = {
    Name        = "secure-cloud-app-database-secret"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }
}
