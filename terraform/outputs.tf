output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets across both Availability Zones"
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}

output "app_subnet_ids" {
  description = "IDs of the private application subnets across both Availability Zones"
  value = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]
}

output "data_subnet_ids" {
  description = "IDs of the private data subnets across both Availability Zones"
  value = [
    aws_subnet.data_a.id,
    aws_subnet.data_b.id
  ]
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

output "alb_dns_name" {
  description = "DNS name of the internet-facing Application Load Balancer"
  value       = var.enable_runtime_resources ? aws_lb.app[0].dns_name : null
}

output "rds_endpoint" {
  description = "Endpoint of the private PostgreSQL RDS instance"
  value       = var.enable_runtime_resources ? aws_db_instance.postgres[0].endpoint : null
}

output "rds_master_secret_arn" {
  description = "ARN of the RDS-managed master user secret"
  value       = var.enable_runtime_resources ? aws_db_instance.postgres[0].master_user_secret[0].secret_arn : null
}

output "vpc_flow_logs_log_group" {
  description = "CloudWatch Logs group containing VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket storing CloudTrail audit logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_name" {
  description = "Name of the project CloudTrail trail"
  value       = aws_cloudtrail.main.name
}