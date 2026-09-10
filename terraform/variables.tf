variable "vpc_cidr" {
  description = "CIDR block for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_runtime_resources" {
  description = "Whether to deploy premium runtime resources such as EC2 and VPC Interface Endpoints"
  type        = bool
  default     = true
}