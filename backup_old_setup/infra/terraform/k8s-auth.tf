resource "kubernetes_secret" "ghcr_creds" {
  metadata {
    name      = "ghcr-creds"
    namespace = "eks-mongo-todo"
  }
  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = base64encode(jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_token
          email    = var.ghcr_email
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    }))
  }
}
