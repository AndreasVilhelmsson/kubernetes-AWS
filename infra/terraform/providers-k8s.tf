data "aws_eks_cluster" "this" { name = module.eks.cluster_name }
data "aws_eks_cluster_auth" "this" { name = module.eks.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  # Note: Ingress-nginx was installed manually via helm CLI due to timeout issues
  # helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace --wait=false
}
