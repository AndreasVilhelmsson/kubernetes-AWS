# EKS MongoDB Todo - Solution Documentation

## Overview
This document describes the final working solution for deploying a full-stack application (MongoDB, Backend API, Frontend) on AWS EKS using Terraform.

## Architecture

### Infrastructure Components
- **VPC**: Custom VPC with public subnets (10.0.0.0/16)
- **EKS Cluster**: Kubernetes 1.29 cluster named "todo-eks"
- **Node Group**: Single t3.small spot instance in public subnets
- **EBS CSI Driver**: For persistent storage with IAM role
- **Network Load Balancer**: For public ingress traffic

### Application Components
- **MongoDB**: StatefulSet with 5Gi persistent volume (gp3)
- **Backend API**: .NET deployment with MongoDB connection
- **Frontend**: Web UI deployment
- **Ingress**: NGINX Ingress Controller for routing

## Key Configuration Decisions

### 1. Cost Optimization
```hcl
enable_nat_gateway = false  # Avoid NAT Gateway costs
use_spot = true             # Use spot instances
node_instance_type = "t3.small"
```

### 2. Network Configuration
- Nodes deployed in **public subnets** (no NAT Gateway required)
- Public subnets tagged for ELB discovery:
  ```hcl
  "kubernetes.io/role/elb" = "1"
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  ```

### 3. EBS CSI Driver IAM
Created dedicated IAM role with IRSA (IAM Roles for Service Accounts):
```hcl
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

### 4. Provider Configuration
Kubernetes and Helm providers configured to connect to EKS:
```hcl
data "aws_eks_cluster" "this" { name = module.eks.cluster_name }
data "aws_eks_cluster_auth" "this" { name = module.eks.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

### 5. Two-Phase Deployment
**Phase 1**: Infrastructure only
- VPC, EKS cluster, node group
- Kubernetes/Helm providers commented out

**Phase 2**: Applications
- Uncomment providers
- Deploy EBS CSI, MongoDB, Backend, Frontend
- Install Ingress manually (Helm timeout issues)

## File Structure
```
infra/terraform/
├── versions.tf           # Provider versions
├── providers.tf          # AWS provider
├── providers-k8s.tf      # Kubernetes/Helm providers
├── vpc.tf               # VPC configuration
├── eks.tf               # EKS cluster
├── addons-ingress.tf    # EBS CSI + Ingress (commented)
├── apply-k8s.tf         # K8s manifests
├── variables.tf         # Input variables
└── outputs.tf           # Outputs

k8s/
├── storageclass-ebs-gp3.yaml
├── mongo/
│   ├── service.yaml
│   └── statefulset.yaml
├── backend/
│   ├── svc.yaml
│   └── deploy.yaml
├── frontend/
│   ├── svc.yaml
│   └── deploy.yaml
└── ingress/
    └── todo-ingress.yaml
```

## Module Versions
```hcl
terraform >= 1.5.0
aws provider ~> 5.0
kubernetes provider >= 2.26.0
helm provider ~> 2.12

eks module ~> 19.0
vpc module ~> 5.0
```

## Deployment Steps

### 1. Initial Infrastructure
```bash
cd infra/terraform
terraform init
terraform apply
```

### 2. Configure kubectl
```bash
aws eks update-kubeconfig --region eu-west-1 --name todo-eks
```

### 3. Deploy Applications
Uncomment providers-k8s.tf and apply-k8s.tf:
```bash
terraform apply
```

### 4. Install Ingress (Manual)
```bash
kubectl delete validatingwebhookconfiguration ingress-nginx-admission
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace --wait=false
```

### 5. Deploy Ingress Resource
```bash
terraform apply
```

## Verification
```bash
# Check all pods
kubectl get pods -n eks-mongo-todo
kubectl get pods -n ingress-nginx

# Get Load Balancer URL
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Test application
curl http://<LOAD_BALANCER_URL>
```

## Outputs
```
cluster_endpoint          = EKS API endpoint
cluster_name             = "todo-eks"
cluster_oidc_provider_arn = For IRSA
vpc_id                   = VPC ID
public_subnets           = Subnet IDs
```

## Security Considerations
- Cluster endpoint is public (for simplicity)
- MongoDB uses default credentials (change in production)
- No network policies configured
- Spot instances may be interrupted

## Cost Estimate
- EKS Control Plane: ~$73/month
- t3.small spot: ~$5/month
- EBS gp3 5GB: ~$0.40/month
- NLB: ~$16/month
- **Total: ~$95/month**

## Cleanup
```bash
terraform destroy
```

Note: May need to manually delete Load Balancer if Terraform fails.
