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