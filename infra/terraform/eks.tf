module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 20.31"

  name               = var.cluster_name
  kubernetes_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      instance_types = ["t3.small"]
    }
  }

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::701055076605:user/adminAndreas"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = {
    vpc-cni    = { most_recent = true }
    kube-proxy = { most_recent = true }
    coredns = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
      timeouts = {
        create = "30m"
        update = "30m"
      }
    }
  }
}

output "cluster_name" { value = module.eks.cluster_name }
