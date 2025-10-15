# ==== GHCR / container registry ====
variable "ghcr_username" {
  description = "GitHub användarnamn (för GHCR)."
  type        = string
  default     = "andreasvilhelmsson" # byt vid behov
}
variable "ghcr_token" {
  description = "PAT för GHCR (write/read). LÄS IN VIA TF_VAR_ghcr_token."
  type        = string
  sensitive   = true
  default     = "" # tomt => ingen secret skapas
}
variable "create_ghcr_secret" {
  description = "Ska vi skapa imagePullSecrets? (behövs bara för privata images)"
  type        = bool
  default     = true
}
variable "kubeconfig_path" {
  description = "Sökväg till kubeconfig som Terraform ska använda."
  type        = string
  default     = "${path.module}/../../kubeconfig.yaml"
}

variable "kube_context" {
  description = "Kube context / namn på klustret i kubeconfig."
  type        = string
  default     = "todo-eks"
}

variable "k8s_namespace" {
  description = "Namnet på ditt Kubernetes-namespace."
  type        = string
  default     = "eks-mongo-todo"
}
variable "ghcr_email" {
  type    = string
  default = "dev@example.com"
}
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}
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
