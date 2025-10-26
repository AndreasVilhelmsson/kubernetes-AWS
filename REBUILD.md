# Rebuild Instructions - Full IaC Recovery

Detta dokument beskriver hur du river och återbygger hela infrastrukturen från scratch med Terraform.

## ✅ IaC Status

Alla komponenter är nu definierade i Terraform:
- ✅ VPC med public/private subnets
- ✅ EKS cluster med 2 t3.small spot nodes
- ✅ EBS CSI Driver med IAM role (IRSA)
- ✅ NGINX Ingress Controller via Helm
- ✅ Security group rule för inter-node traffic
- ✅ Kubernetes manifests (namespace, MongoDB, backend, frontend, ingress)

## 🔧 Prerequisites

```bash
# Installera verktyg
brew install terraform awscli kubectl helm

# Konfigurera AWS credentials
aws configure
# AWS Access Key ID: <din-key>
# AWS Secret Access Key: <din-secret>
# Default region: eu-west-1
# Default output format: json

# Verifiera
aws sts get-caller-identity
```

## 🗑️ Destroy (Riva ner allt)

```bash
cd infra/terraform

# Destroy i rätt ordning (viktigt!)
terraform destroy -target=kubernetes_manifest.ingress
terraform destroy -target=helm_release.ingress_nginx
terraform destroy -target=module.eks
terraform destroy -target=module.vpc

# Eller destroy allt på en gång (kan ta 15-20 min)
terraform destroy -auto-approve
```

**Manuell cleanup om något fastnar:**
```bash
# Ta bort Load Balancer manuellt
aws elb describe-load-balancers --region eu-west-1
aws elb delete-load-balancer --load-balancer-name <name>

# Ta bort EBS volumes
aws ec2 describe-volumes --region eu-west-1 --filters "Name=tag:Project,Values=eks-mongo-todo"
aws ec2 delete-volume --volume-id <vol-id>
```

## 🚀 Rebuild (Bygg upp från scratch)

### Steg 1: Terraform Init
```bash
cd infra/terraform
terraform init
```

### Steg 2: Terraform Plan
```bash
terraform plan

# Förväntat output:
# Plan: 51 to add, 0 to change, 0 to destroy
```

### Steg 3: Terraform Apply
```bash
terraform apply

# Eller auto-approve för att skippa confirmation:
terraform apply -auto-approve
```

**Väntetid:** ~15-20 minuter för EKS cluster + nodes + addons

### Steg 4: Konfigurera kubectl
```bash
aws eks update-kubeconfig --region eu-west-1 --name todo-eks

# Verifiera
kubectl get nodes
# Förväntat: 2 nodes i Ready state
```

### Steg 5: Vänta på Ingress Controller
```bash
# Kolla att ingress-nginx pods är running
kubectl get pods -n ingress-nginx -w

# Vänta på Load Balancer (kan ta 2-3 min)
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
# Vänta tills EXTERNAL-IP inte är <pending>
```

### Steg 6: Verifiera Deployment
```bash
# Kolla alla pods
kubectl get pods -n eks-mongo-todo

# Förväntat output:
# NAME                             READY   STATUS
# mongodb-0                        1/1     Running
# todo-backend-xxx                 1/1     Running
# todo-frontend-xxx                1/1     Running

# Kolla ingress
kubectl get ingress -n eks-mongo-todo

# Hämta Load Balancer URL
LB_URL=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Application URL: http://$LB_URL"
```

### Steg 7: Testa Applikationen
```bash
# Testa frontend
curl -I http://$LB_URL

# Testa backend API
curl http://$LB_URL/api/todos

# Öppna i browser
open http://$LB_URL
```

## 🔍 Troubleshooting

### Pods i Pending state
```bash
kubectl describe pod <pod-name> -n eks-mongo-todo

# Vanliga orsaker:
# - Insufficient CPU/memory: Öka node count eller size
# - PVC pending: Kolla EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi
```

### 504 Gateway Timeout
```bash
# Kolla security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw node_security_group_id) \
  --region eu-west-1

# Verifiera att inter-node rule finns:
# IpProtocol: -1, SourceSecurityGroupId: <samma-sg-id>
```

### Ingress 404 errors
```bash
# Kolla ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100

# Kolla ingress configuration
kubectl describe ingress todo-ingress -n eks-mongo-todo
```

### EBS CSI Driver DEGRADED
```bash
# Kolla addon status
aws eks describe-addon \
  --cluster-name todo-eks \
  --addon-name aws-ebs-csi-driver \
  --region eu-west-1

# Kolla IAM role
aws iam get-role --role-name todo-eks-ebs-csi-driver

# Kolla pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

## 📊 Verify IaC Completeness

Kör detta script för att verifiera att allt är i Terraform state:

```bash
#!/bin/bash
echo "=== Terraform Resources ==="
terraform state list | wc -l
echo "resources in state"

echo -e "\n=== AWS Resources ==="
echo "VPC: $(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=eks-mongo-todo" --query 'Vpcs[0].VpcId' --output text)"
echo "EKS: $(aws eks describe-cluster --name todo-eks --query 'cluster.status' --output text)"
echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
echo "Pods: $(kubectl get pods -n eks-mongo-todo --no-headers | wc -l)"
echo "Ingress: $(kubectl get ingress -n eks-mongo-todo --no-headers | wc -l)"
```

## 🎯 Success Criteria

Efter rebuild ska följande vara sant:
- ✅ 2 worker nodes i Ready state
- ✅ 3 application pods running (mongodb, backend, frontend)
- ✅ Ingress med Load Balancer URL
- ✅ Application accessible via browser
- ✅ API calls fungerar (GET /api/todos)
- ✅ Kan skapa och ta bort todos

## 💰 Cost Reminder

**Månadskostnad:** ~$100
- EKS Control Plane: $73
- 2x t3.small spot: ~$10
- EBS: $0.40
- NLB: ~$16

**Stäng av när du inte använder:**
```bash
# Destroy för att undvika kostnader
terraform destroy -auto-approve
```

## 📝 Notes

- **Första apply:** Kan ta 20+ minuter
- **Destroy:** Kan ta 15+ minuter
- **State file:** Sparas lokalt i `terraform.tfstate` (lägg INTE i Git!)
- **Secrets:** MongoDB credentials är hårdkodade (ej production-ready)
- **Images:** Pullas från GitHub Container Registry (public)
