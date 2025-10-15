terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.8"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }

  required_version = ">= 1.6.0"
}

# ==== AWS PROVIDER ====
provider "aws" {
  region = var.region
}

# ==== KUBERNETES PROVIDER ====
# används av Terraform-resurser (ex: secrets, configmaps)
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# ==== KUBECTL PROVIDER ====
# används för att applicera YAML-filer (t.ex. deployment/service)
provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
