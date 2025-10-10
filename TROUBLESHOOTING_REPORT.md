# EKS Todo App - Troubleshooting Report
**Datum:** 2025-10-09  
**Status:** Pågående - Klustret är skapat men saknar fungerande noder

---

## Sammanfattning
Vi försökte sätta upp ett EKS-kluster med Terraform men stötte på flera problem:
1. ✅ CoreDNS timeout - LÖST
2. ✅ Kubeconfig autentisering - LÖST  
3. ✅ IAM access till kluster - LÖST
4. ❌ EKS Auto Mode fungerade inte - BYTTE till Managed Node Groups
5. ❌ Node Group skapande misslyckades (Free Tier problem) - PÅGÅENDE

---

## Problem 1: CoreDNS Add-on Timeout

### Symptom
```
Error: waiting for EKS Add-On (todo-eks:coredns) create: timeout while waiting 
for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)
```

### Orsak
- CoreDNS timeout på 20 minuter var för kort
- Ingen `resolve_conflicts` konfiguration

### Lösning
**Fil:** `infra/terraform/eks.tf`

```hcl
addons = {
  coredns = {
    most_recent = true
    resolve_conflicts = "OVERWRITE"  # Lägg till denna
    timeouts = {
      create = "30m"  # Öka från 20m till 30m
      update = "30m"
    }
  }
}
```

**Kommandon körda:**
```bash
# Ta bort CoreDNS från Terraform state
terraform state rm 'module.eks.aws_eks_addon.this["coredns"]'

# Importera tillbaka
terraform import 'module.eks.aws_eks_addon.this["coredns"]' todo-eks:coredns

# Applicera ny konfiguration
terraform apply
```

**Vad koden gör:**
- `resolve_conflicts = "OVERWRITE"` - Skriver över befintlig CoreDNS-konfiguration vid konflikter
- `timeouts` - Ger mer tid för add-on att bli redo

---

## Problem 2: Kubeconfig Autentisering

### Symptom
```
Please enter Username:
```
eller
```
error: the server has asked for the client to provide credentials
```

### Orsak
- Kubeconfig hade tomt `token: ""` fält
- Saknade AWS CLI exec-konfiguration

### Lösning 1: Uppdatera Terraform kubeconfig
**Fil:** `infra/terraform/kubeconfig.tf`

```hcl
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
```

### Lösning 2: Använd AWS CLI för kubeconfig
```bash
aws eks update-kubeconfig --name todo-eks --region eu-west-1 --kubeconfig kubeconfig-aws.yaml
```

**Vad koden gör:**
- `exec` - Kör AWS CLI för att hämta temporär token vid varje kubectl-kommando
- `aws eks get-token` - Genererar en giltig Kubernetes-token från dina AWS-credentials

---

## Problem 3: Cluster Endpoint Access

### Symptom
```
dial tcp 10.77.100.78:443: i/o timeout
```

### Orsak
- Klustret hade bara privat endpoint (10.x.x.x)
- Kunde inte nås från lokal maskin

### Lösning
**Fil:** `infra/terraform/eks.tf`

```hcl
module "eks" {
  endpoint_public_access = true  # Lägg till denna rad
}
```

**Kommando:**
```bash
terraform apply
```

**Vad koden gör:**
- Aktiverar publik endpoint för EKS API-server
- Gör att du kan köra kubectl från din lokala maskin

---

## Problem 4: IAM Access till Kluster

### Symptom
```
error: You must be logged in to the server (the server has asked for the 
client to provide credentials)
```

### Orsak
- IAM-användaren `adminAndreas` hade inte tillgång till klustret
- EKS använder access entries för autentisering

### Lösning
**Fil:** `infra/terraform/eks.tf`

```hcl
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
```

**Kommando:**
```bash
terraform apply
```

**Vad koden gör:**
- `access_entries` - Ger IAM-användare tillgång till klustret
- `AmazonEKSClusterAdminPolicy` - Ger full admin-access till klustret
- `access_scope: cluster` - Access gäller hela klustret

---

## Problem 5: EKS Auto Mode Fungerade Inte

### Symptom
```
no nodes available to schedule pods
```
Pods stannade i "Pending" state trots att Auto Mode var aktiverat.

### Orsak
- EKS Auto Mode (Kubernetes 1.34) provisionerade inte noder automatiskt
- `nodePools` var tom: `{"enabled": true, "nodePools": []}`

### Lösning
Bytte från Auto Mode till Managed Node Groups.

**Före:**
```hcl
compute_config = { enabled = true }
```

**Efter:**
```hcl
eks_managed_node_groups = {
  default = {
    min_size     = 1
    max_size     = 2
    desired_size = 1
    instance_types = ["t3.small"]
  }
}
```

**Vad koden gör:**
- `eks_managed_node_groups` - Skapar en grupp av EC2-instanser som Kubernetes-noder
- `min_size/max_size` - Auto-scaling gränser
- `desired_size` - Antal noder som ska köra
- `instance_types` - EC2-instanstyp (t3.small = 2 vCPU, 2GB RAM)

---

## Problem 6: Node Group Creation Failed (PÅGÅENDE)

### Symptom
```
status: "CREATE_FAILED"
code: "AsgInstanceLaunchFailures"
message: "The specified instance type is not eligible for Free Tier"
```

### Orsak
- Försökte använda `t3.medium` som inte är Free Tier
- Bytte till `t3.micro` men det är för litet för EKS (1GB RAM)

### Lösning
Använd `t3.small` (minsta rekommenderade storlek för EKS).

**Kommandon att köra imorgon:**
```bash
# 1. Kolla om misslyckad node group finns kvar
aws eks list-nodegroups --cluster-name todo-eks --region eu-west-1

# 2. Ta bort den misslyckade node group
aws eks delete-nodegroup \
  --cluster-name todo-eks \
  --nodegroup-name default-20251009230709335900000001 \
  --region eu-west-1

# 3. Vänta 2-3 minuter, verifiera att den är borta
aws eks list-nodegroups --cluster-name todo-eks --region eu-west-1

# 4. Applicera Terraform med t3.small
cd infra/terraform
terraform apply
```

**Vad koden gör:**
- `t3.small` - 2 vCPU, 2GB RAM (~$0.02/timme = ~$15/månad)
- Tillräckligt med resurser för EKS system-komponenter + din app

---

## Aktuell Infrastruktur Status

### ✅ Fungerar
- VPC med public/private subnets
- NAT Gateways
- EKS Cluster (todo-eks)
- EKS Add-ons (vpc-cni, kube-proxy, coredns)
- IAM Roles och Policies
- Public endpoint access
- Kubeconfig autentisering

### ❌ Fungerar Inte
- Inga fungerande noder (node group misslyckades)
- CoreDNS är DEGRADED (väntar på noder)
- Kan inte köra pods

---

## Komplett IaC Setup (Från Scratch)

### Steg 1: Förberedelser
```bash
cd /Users/andreasdator/Desktop/kubernetes/eks-mongo-todo/infra/terraform
```

### Steg 2: Initiera Terraform
```bash
terraform init
```

### Steg 3: Applicera Infrastruktur
```bash
terraform apply
```

Detta skapar:
- VPC (10.0.0.0/16)
- 2 Public Subnets (10.0.1.0/24, 10.0.2.0/24)
- 2 Private Subnets (10.0.101.0/24, 10.0.102.0/24)
- Internet Gateway
- 2 NAT Gateways (en per AZ)
- EKS Cluster (Kubernetes 1.34)
- Managed Node Group (1x t3.small)
- EKS Add-ons (vpc-cni, kube-proxy, coredns)

**Tid:** ~15-20 minuter

### Steg 4: Konfigurera kubectl
```bash
aws eks update-kubeconfig --name todo-eks --region eu-west-1
```

### Steg 5: Verifiera
```bash
kubectl get nodes
kubectl get pods -A
```

### Steg 6: Riva Ner Allt
```bash
# Ta bort Kubernetes-resurser först
kubectl delete deployment test-app

# Riva ner infrastruktur
terraform destroy
```

**Tid:** ~10-15 minuter

---

## Terraform State Management Problem

### Problem
Terraform state-fil blev låst när processer avbröts.

### Symptom
```
Error: Error acquiring the state lock
Lock Info:
  ID: c970244e-ae2c-bdab-a9ef-b02a97247e28
```

### Lösning
```bash
# Hitta låsta processer
ps aux | grep terraform

# Döda dem
kill -9 <PID>

# Eller använd force unlock (ej rekommenderat)
terraform force-unlock c970244e-ae2c-bdab-a9ef-b02a97247e28
```

---

## Kostnadsuppskattning

### Aktuell Konfiguration
- **EKS Cluster:** $0.10/timme = $73/månad
- **1x t3.small node:** $0.0208/timme = $15/månad
- **2x NAT Gateway:** $0.045/timme × 2 = $65/månad
- **Data transfer:** ~$5-10/månad

**Total:** ~$158-163/månad

### Optimering för Lägre Kostnad
1. Ta bort NAT Gateways (använd public subnets för noder)
2. Använd Fargate istället för EC2 nodes
3. Stäng av klustret när det inte används

---

## Nästa Steg (Imorgon)

1. ✅ Ta bort misslyckad node group
2. ✅ Applicera Terraform med t3.small
3. ✅ Verifiera att noder startar
4. ✅ Verifiera att CoreDNS blir ACTIVE
5. ⬜ Deploya MongoDB
6. ⬜ Deploya Backend
7. ⬜ Deploya Frontend
8. ⬜ Testa applikationen

---

## Lärdomar

### Vad Fungerade Bra
- Terraform modules för VPC och EKS
- AWS CLI för debugging
- Stegvis felsökning

### Vad Fungerade Dåligt
- EKS Auto Mode är inte produktionsredo (Kubernetes 1.34)
- Free Tier begränsningar för EKS
- Terraform state locking vid avbrott

### Rekommendationer
1. **Använd alltid Managed Node Groups** - Mer stabilt än Auto Mode
2. **Budgetera för EKS** - Det är inte gratis (minst $88/månad)
3. **Testa lokalt först** - Använd minikube/kind för utveckling
4. **Dokumentera allt** - Spara alla kommandon och felmeddelanden

---

## Filer Skapade/Modifierade

### Terraform-filer
- `infra/terraform/eks.tf` - EKS cluster konfiguration
- `infra/terraform/vpc.tf` - VPC och nätverk
- `infra/terraform/vpc-endpoints.tf` - VPC endpoints för S3
- `infra/terraform/kubeconfig.tf` - Kubeconfig generering
- `infra/terraform/providers.tf` - AWS provider
- `infra/terraform/variables.tf` - Variabler

### Kubernetes-filer
- `k8s/test-deployment.yaml` - Test deployment för att trigga node-skapande
- `k8s/namespace.yaml` - Namespace för applikationen
- `k8s/mongo/` - MongoDB deployment och service
- `k8s/backend/` - Backend deployment, service, config, secret

### Genererade filer
- `kubeconfig.yaml` - Terraform-genererad kubeconfig
- `kubeconfig-aws.yaml` - AWS CLI-genererad kubeconfig

---

## Användbara Kommandon

### Terraform
```bash
terraform init              # Initiera Terraform
terraform plan              # Visa vad som kommer att ändras
terraform apply             # Applicera ändringar
terraform destroy           # Riva ner allt
terraform state list        # Lista alla resurser i state
terraform state rm <resurs> # Ta bort resurs från state
terraform import <resurs>   # Importera befintlig resurs
```

### AWS CLI - EKS
```bash
# Lista kluster
aws eks list-clusters --region eu-west-1

# Beskriv kluster
aws eks describe-cluster --name todo-eks --region eu-west-1

# Lista node groups
aws eks list-nodegroups --cluster-name todo-eks --region eu-west-1

# Beskriv node group
aws eks describe-nodegroup --cluster-name todo-eks --nodegroup-name <name> --region eu-west-1

# Ta bort node group
aws eks delete-nodegroup --cluster-name todo-eks --nodegroup-name <name> --region eu-west-1

# Uppdatera kubeconfig
aws eks update-kubeconfig --name todo-eks --region eu-west-1
```

### kubectl
```bash
# Visa noder
kubectl get nodes

# Visa alla pods
kubectl get pods -A

# Beskriv pod (för debugging)
kubectl describe pod <pod-name> -n <namespace>

# Visa logs
kubectl logs <pod-name> -n <namespace>

# Applicera manifest
kubectl apply -f <file.yaml>

# Ta bort resurser
kubectl delete -f <file.yaml>
```

### AWS CLI - EC2
```bash
# Lista EC2-instanser för klustret
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=todo-eks" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' \
  --output table \
  --region eu-west-1
```

---

## Kontaktinformation för Support
- AWS Support: https://console.aws.amazon.com/support/
- Terraform AWS Provider Issues: https://github.com/hashicorp/terraform-provider-aws/issues
- EKS Documentation: https://docs.aws.amazon.com/eks/

---

**Slutsats:** Infrastrukturen är nästan klar. Sista steget är att få node group att skapas med t3.small instanser. Efter det kan vi deploya applikationen.
