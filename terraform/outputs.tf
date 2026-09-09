output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the project VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "app_subnet_id" {
  description = "ID of the private application subnet"
  value       = aws_subnet.app.id
}

output "data_subnet_id" {
  description = "ID of the private data subnet"
  value       = aws_subnet.data.id
}

output "internet_gateway_id" {
  description = "ID of the VPC Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "app_instance_id" {
  description = "ID of the private application EC2 instance"
  value       = var.enable_runtime_resources ? aws_instance.app[0].id : null
}

output "app_instance_private_ip" {
  description = "Private IP address of the application EC2 instance"
  value       = var.enable_runtime_resources ? aws_instance.app[0].private_ip : null
}

output "app_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "app_secret_name" {
  description = "Name of the application database secret"
  value       = aws_secretsmanager_secret.app.name
}

output "app_secret_arn" {
  description = "ARN of the application database secret"
  value       = aws_secretsmanager_secret.app.arn
}

output "rds_endpoint" {
  value = var.enable_runtime_resources ? aws_db_instance.postgres[0].endpoint : null
}

output "rds_master_secret_arn" {
  value = var.enable_runtime_resources ? aws_db_instance.postgres[0].master_user_secret[0].secret_arn : null
}