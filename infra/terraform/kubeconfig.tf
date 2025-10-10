data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

resource "local_file" "kubeconfig" {
  filename = "${path.module}/../../kubeconfig.yaml"
  content  = <<-YAML
apiVersion: v1
clusters:
- cluster:
    server: ${data.aws_eks_cluster.this.endpoint}
    certificate-authority-data: ${data.aws_eks_cluster.this.certificate_authority[0].data}
  name: ${module.eks.cluster_name}
contexts:
- context:
    cluster: ${module.eks.cluster_name}
    user: ${module.eks.cluster_name}
  name: ${module.eks.cluster_name}
current-context: ${module.eks.cluster_name}
kind: Config
users:
- name: ${module.eks.cluster_name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - ${module.eks.cluster_name}
        - --region
        - eu-west-1
YAML
}
