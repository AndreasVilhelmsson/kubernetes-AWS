provider "kubectl" {
  config_path    = "${path.module}/../../kubeconfig.yaml"
  config_context = "todo-eks"
}

resource "kubectl_manifest" "namespace" {
  yaml_body = file("${path.module}/../../k8s/namespace.yaml")
}
# --- Deploy MongoDB Service ---
resource "kubectl_manifest" "mongo_svc" {
  yaml_body  = file("${path.module}/../../k8s/mongo/mongo-svc.yaml")
  depends_on = [kubectl_manifest.namespace]
}

# --- Deploy MongoDB Deployment ---
resource "kubectl_manifest" "mongo_deploy" {
  yaml_body  = file("${path.module}/../../k8s/mongo/mongo-deploy.yaml")
  depends_on = [kubectl_manifest.mongo_svc]
}

# --- Backend ---
resource "kubectl_manifest" "backend_secret" {
  depends_on = [kubectl_manifest.namespace]
  yaml_body  = file("${path.module}/../../k8s/backend/secret.yaml")
}
resource "kubectl_manifest" "backend_config" {
  depends_on = [kubectl_manifest.backend_secret]
  yaml_body  = file("${path.module}/../../k8s/backend/config.yaml")
}
resource "kubectl_manifest" "backend_deploy" {
  depends_on = [kubectl_manifest.backend_config]
  yaml_body  = file("${path.module}/../../k8s/backend/deploy.yaml")
}
resource "kubectl_manifest" "backend_svc" {
  depends_on = [kubectl_manifest.backend_deploy]
  yaml_body  = file("${path.module}/../../k8s/backend/svc.yaml")
}

# --- Frontend ---
resource "kubectl_manifest" "frontend_deploy" {
  depends_on = [kubectl_manifest.backend_svc]
  yaml_body  = file("${path.module}/../../k8s/frontend/deploy.yaml")
}
resource "kubectl_manifest" "frontend_svc" {
  depends_on = [kubectl_manifest.frontend_deploy]
  yaml_body  = file("${path.module}/../../k8s/frontend/svc.yaml")
}
