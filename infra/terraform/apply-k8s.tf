resource "kubernetes_manifest" "sc_gp3" {
  manifest   = yamldecode(file("${path.module}/../../k8s/storageclass-ebs-gp3.yaml"))
  depends_on = [aws_eks_addon.ebs_csi]
}

resource "kubernetes_manifest" "mongo_svc" {
  manifest   = yamldecode(file("${path.module}/../../k8s/mongo/service.yaml"))
  depends_on = [kubernetes_namespace.project]
}

resource "kubernetes_manifest" "mongo" {
  manifest   = yamldecode(file("${path.module}/../../k8s/mongo/statefulset.yaml"))
  depends_on = [kubernetes_manifest.sc_gp3, kubernetes_manifest.mongo_svc]
}

resource "kubernetes_manifest" "backend_svc" {
  manifest   = yamldecode(file("${path.module}/../../k8s/backend/svc.yaml"))
  depends_on = [kubernetes_namespace.project]
}

resource "kubernetes_manifest" "backend_deploy" {
  manifest = yamldecode(
    replace(file("${path.module}/../../k8s/backend/deploy.yaml"), "%%IMAGE%%", var.backend_image)
  )
  depends_on = [kubernetes_manifest.backend_svc, kubernetes_manifest.mongo]
}

resource "kubernetes_manifest" "frontend_svc" {
  manifest   = yamldecode(file("${path.module}/../../k8s/frontend/svc.yaml"))
  depends_on = [kubernetes_namespace.project]
}

resource "kubernetes_manifest" "frontend_deploy" {
  manifest = yamldecode(
    replace(file("${path.module}/../../k8s/frontend/deploy.yaml"), "%%IMAGE%%", var.frontend_image)
  )
  depends_on = [kubernetes_manifest.frontend_svc]
}

resource "kubernetes_manifest" "ingress" {
  count    = var.enable_ingress ? 1 : 0
  manifest = yamldecode(file("${path.module}/../../k8s/ingress/todo-ingress.yaml"))
  depends_on = [
    kubernetes_manifest.frontend_deploy,
    kubernetes_manifest.backend_deploy
  ]
}

resource "kubernetes_namespace" "project" {
  metadata {
    name = var.project_ns
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = var.tags["Project"]
      "owner"                        = var.tags["Owner"]
      "environment"                  = var.tags["Environment"]
    }
  }
}
