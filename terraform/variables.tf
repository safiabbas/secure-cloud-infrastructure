variable "vpc_cidr" {
  description = "CIDR block for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_runtime_resources" {
  description = "Whether to deploy temporary runtime resources such as NAT Gateway and EC2"
  type        = bool
  default     = false
}