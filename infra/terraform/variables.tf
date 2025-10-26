variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "cluster_name" {
  type    = string
  default = "todo-eks"
}

variable "project_ns" {
  type    = string
  default = "eks-mongo-todo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
# Pick two AZs for lower cost (fewer NATs, fewer subnets)
variable "azs" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

# /20 per AZ -> two /24 publics + two /24 privates (simple)
variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
} # set false to avoid NAT cost (see note below)

# Alla resurser taggas med detta
variable "tags" {
  type = map(string)
  default = {
    Project     = "eks-mongo-todo"
    Owner       = "andreasvilhelmsson"
    Environment = "dev"
    ManagedBy   = "terraform"
    CostCenter  = "student-lab"
  }
}

# Billig drift
variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 2
}

variable "use_spot" {
  type    = bool
  default = true
}

# Kostnadsbrytare för publik ingress (NLB kostar per timme)
variable "enable_ingress" {
  type    = bool
  default = true
}

# Containerbilder (från dina GitHub Actions)
variable "backend_image" {
  type    = string
  default = "ghcr.io/andreasvilhelmsson/todo-backend-v2:latest"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/andreasvilhelmsson/todo-frontend-v2:latest"
}
