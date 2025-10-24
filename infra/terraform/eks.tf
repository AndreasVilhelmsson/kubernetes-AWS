module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name # t.ex. "todo-eks"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  # Billigaste setup: 1 spot-node
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2_x86_64"
      capacity_type  = var.use_spot ? "SPOT" : "ON_DEMAND"
      instance_types = [var.node_instance_type] # t3.small

      desired_size = var.node_min
      min_size     = var.node_min
      max_size     = var.node_max

      labels = {
        workload = "apps"
      }

      tags = var.tags
    }
  }

  tags = var.tags
}
