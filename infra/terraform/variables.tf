variable "region" { default = "eu-west-1" }
variable "cluster_name" { default = "todo-eks" }

# Eget VPC (unika CIDRs)
variable "vpc_cidr" { default = "10.77.0.0/16" }
variable "public_subnets" {
  type    = list(string)
  default = ["10.77.0.0/24", "10.77.1.0/24"]
}
variable "private_subnets" {
  type    = list(string)
  default = ["10.77.100.0/24", "10.77.101.0/24"]
}

# Valfritt endpoint till S3
variable "enable_s3_endpoint" {
  type    = bool
  default = true
}
