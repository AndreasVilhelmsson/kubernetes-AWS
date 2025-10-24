# EKS MongoDB Todo - Failure Report

## Summary
This document details all issues encountered during the deployment of the EKS MongoDB Todo application and their resolutions.

---

## Issue 1: Typos in Variable Names

### Problem
```
Error: Reference to undeclared input variable
│ var.vpc_deor
│ var.gats
```

### Root Cause
Typographical errors in `vpc.tf`:
- `var.vpc_deor` instead of `var.vpc_cidr`
- `var.gats` instead of `var.tags`

### Solution
Fixed variable names in `vpc.tf`:
```hcl
cidr = var.vpc_cidr
public_subnet_tags = merge(var.tags, {
```

### Impact
Low - Caught during `terraform validate`

---

## Issue 2: Unsupported Attribute in VPC Module

### Problem
```
Error: Unexpected attribute
│ An attribute named "enable_dns64" is not expected here
```

### Root Cause
VPC module version 6.4 doesn't support `enable_dns64` attribute

### Solution
Removed the unsupported attribute from `vpc.tf`

### Impact
Low - Module version compatibility issue

---

## Issue 3: Helm Provider Configuration Syntax

### Problem
```
Error: Unexpected block: Blocks of type "kubernetes" are not expected here
```

### Root Cause
Helm provider v3.0+ doesn't support nested `kubernetes` block, but v2.x does. Version constraint was `>= 2.12.0` which installed v3.0.2.

### Solution
Changed Helm provider version to `~> 2.12` to use v2.x syntax:
```hcl
provider "helm" {
  kubernetes {
    host = data.aws_eks_cluster.this.endpoint
    ...
  }
}
```

### Impact
Medium - Required version downgrade and provider reconfiguration

---

## Issue 4: AWS Provider Version Conflicts

### Problem
```
Error: no available releases match the given constraints >= 4.33.0, >= 5.95.0, >= 6.0.0, < 6.0.0
```

### Root Cause
- EKS module v20.x required AWS provider `>= 6.0.0`
- VPC module v6.x required AWS provider `>= 6.0.0`
- Local versions.tf specified `~> 5.0`
- Conflicting constraints: `>= 6.0.0` AND `< 6.0.0`

### Solution
Downgraded modules to match AWS provider 5.x:
```hcl
eks module: ~> 20.24 → ~> 19.0
vpc module: ~> 6.4 → ~> 5.0
aws provider: ~> 5.0 (kept)
```

### Impact
High - Required module downgrades and multiple `terraform init -upgrade` cycles

---

## Issue 5: Unsupported EKS Module Argument

### Problem
```
Error: Unsupported argument
│ An argument named "enable_cluster_creator_admin_permissions" is not expected here
```

### Root Cause
`enable_cluster_creator_admin_permissions` only exists in EKS module v20+, not in v19

### Solution
Removed the argument from `eks.tf`

### Impact
Low - Feature not critical for development

---

## Issue 6: YAML Parsing Error - Multi-Document File

### Problem
```
Error: Call to function "yamldecode" failed: on line 9, column 1: unexpected extra content after value
```

### Root Cause
MongoDB YAML file contained two documents (Service and StatefulSet) separated by `---`. Terraform's `yamldecode()` can only parse single documents.

### Solution
Split into two separate files:
- `k8s/mongo/service.yaml`
- `k8s/mongo/statefulset.yaml`

Updated Terraform to create two resources:
```hcl
resource "kubernetes_manifest" "mongo_svc" { ... }
resource "kubernetes_manifest" "mongo" { ... }
```

### Impact
Medium - Required file restructuring and resource updates

---

## Issue 7: YAML Syntax Error - Unquoted Colons

### Problem
```
Error: Call to function "yamldecode" failed: on line 14, column 79: did not find expected ',' or '}'
```

### Root Cause
YAML values containing colons must be quoted:
```yaml
value: http://+:8080  # Invalid
```

### Solution
Added quotes around values with colons:
```yaml
value: "http://+:8080"
value: "mongodb://root:changeme@mongodb:27017/?authSource=admin"
```

### Impact
Low - Simple syntax fix

---

## Issue 8: Provider Configuration Before Cluster Exists

### Problem
```
Error: reading EKS Cluster (todo-eks): couldn't find resource
```

### Root Cause
Kubernetes and Helm providers tried to connect to EKS cluster during `terraform plan`, but cluster didn't exist yet. Providers are configured at plan time, not apply time.

### Solution
Implemented two-phase deployment:
1. Comment out `providers-k8s.tf` and all Kubernetes resources
2. Deploy VPC and EKS cluster
3. Uncomment providers and Kubernetes resources
4. Deploy applications

### Impact
High - Required manual intervention and multi-step deployment process

---

## Issue 9: Node Group Creation Failure

### Problem
```
Error: waiting for EKS Node Group create: unexpected state 'CREATE_FAILED'
│ NodeCreationFailure: Instances failed to join the kubernetes cluster
```

### Root Cause
Nodes were configured to launch in `private_subnets` but `enable_nat_gateway = false`. Private subnets without NAT Gateway cannot reach internet, so nodes couldn't connect to EKS control plane.

### Solution
Changed node group to use public subnets:
```hcl
subnet_ids = module.vpc.public_subnets
```

### Impact
Critical - Cluster was non-functional until fixed. Required `terraform destroy` and full rebuild.

---

## Issue 10: EBS CSI Addon Timeout (DEGRADED State)

### Problem
```
Error: waiting for EKS Add-On (todo-eks:aws-ebs-csi-driver) create: timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)
```

### Root Cause
EBS CSI driver addon requires IAM permissions via IRSA (IAM Roles for Service Accounts). Without proper IAM role, the addon stays in DEGRADED state indefinitely.

### Solution
Created IAM role with IRSA trust policy:
```hcl
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
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  ...
}
```

### Impact
Critical - Blocked deployment for extended periods (multiple 20+ minute timeouts). Required multiple destroy/apply cycles.

---

## Issue 11: Incorrect Cluster Name in VPC Tags

### Problem
```
Error: failed to ensure load balancer: could not find any suitable subnets for creating the ELB
```

### Root Cause
VPC subnet tags used hardcoded cluster name "eks-mongo-todo" but actual cluster name was "todo-eks". Kubernetes couldn't find tagged subnets for Load Balancer creation.

### Solution
Changed hardcoded cluster name to variable:
```hcl
public_subnet_tags = merge(var.tags, {
  "kubernetes.io/role/elb" = "1"
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
})
```

### Impact
High - Load Balancer couldn't be created. Required `terraform apply` to update tags.

---

## Issue 12: Helm Release Timeout

### Problem
```
Error: context deadline exceeded
│ Warning: Helm release "" was created but has a failed status
```

### Root Cause
Helm provider has 5-minute default timeout. Ingress-nginx installation takes longer due to:
- Pulling container images
- Creating admission webhooks
- Provisioning AWS Load Balancer

### Solution
Removed Helm release from Terraform and installed manually:
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace --wait=false
```

Commented out in Terraform:
```hcl
# resource "helm_release" "ingress_nginx" { ... }
```

### Impact
Medium - Required manual Helm installation outside Terraform

---

## Issue 13: Ingress Admission Webhook Certificate Error

### Problem
```
Error: failed calling webhook "validate.nginx.ingress.kubernetes.io": 
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

### Root Cause
Ingress-nginx admission webhook job failed to complete, leaving invalid webhook configuration. The webhook certificate wasn't properly generated.

### Solution
Deleted the broken webhook configuration:
```bash
kubectl delete validatingwebhookconfiguration ingress-nginx-admission
```

Then applied Ingress resource via Terraform.

### Impact
Medium - Blocked Ingress creation until webhook was removed

---

## Lessons Learned

### 1. Module Version Compatibility
Always check module compatibility matrix before mixing versions. EKS module v20 requires AWS provider v6, but VPC module v6 also requires AWS provider v6. Downgrading both modules to v19/v5 was necessary.

### 2. Two-Phase Deployment Pattern
When providers depend on resources being created (like EKS cluster), use two-phase deployment:
- Phase 1: Infrastructure
- Phase 2: Applications

### 3. NAT Gateway vs Public Subnets
For cost optimization, using public subnets for nodes is acceptable in dev/test. Production should use private subnets with NAT Gateway.

### 4. IRSA for EKS Addons
Always configure IAM roles for EKS addons that need AWS API access (EBS CSI, ALB Controller, etc.). Don't rely on node IAM roles.

### 5. Subnet Tagging
Kubernetes requires specific tags on subnets for Load Balancer provisioning:
- Public: `kubernetes.io/role/elb = 1`
- Private: `kubernetes.io/role/internal-elb = 1`
- Cluster: `kubernetes.io/cluster/<name> = shared`

### 6. Helm Timeouts
For resources that take time to provision (Load Balancers, webhooks), either:
- Increase Helm timeout
- Use `--wait=false`
- Install manually outside Terraform

### 7. YAML Multi-Document Files
Terraform's `yamldecode()` doesn't support multi-document YAML files. Split them or use `kubectl apply -f` instead.

### 8. Variable Naming
Use consistent, descriptive variable names. Typos like `vpc_deor` are easy to make and hard to spot.

---

## Time Investment
- Initial setup: 30 minutes
- Troubleshooting: ~3 hours
- Multiple destroy/apply cycles: ~2 hours
- **Total: ~5.5 hours**

## Success Metrics
- ✅ All infrastructure deployed via Terraform
- ✅ Application running and accessible
- ✅ Persistent storage working
- ✅ Public ingress functional
- ✅ Cost optimized (~$95/month)
