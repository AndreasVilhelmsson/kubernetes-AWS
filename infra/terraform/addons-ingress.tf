data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  tags                     = var.tags
}

# Ingress-NGINX - Install manually with: helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
# resource "helm_release" "ingress_nginx" {
#   count            = var.enable_ingress ? 1 : 0
#   name             = "ingress-nginx"
#   namespace        = "ingress-nginx"
#   repository       = "https://kubernetes.github.io/ingress-nginx"
#   chart            = "ingress-nginx"
#   version          = "4.11.1"
#   create_namespace = true

#   values = [yamlencode({
#     controller = {
#       kind = "Deployment"
#       service = {
#         type = "LoadBalancer"
#         annotations = {
#           "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
#           "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
#           "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
#           # Viktigt: tagga själva NLB-resursen
#           "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags" = join(",", [
#             for k, v in var.tags : "${k}=${v}"
#           ])
#         }
#       }
#     }
#   })]
# }
