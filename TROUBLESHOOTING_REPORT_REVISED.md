# 🧭 TROUBLESHOOTING REPORT – EKS ADD-ON (CoreDNS) DEGRADED STATE

## 🗒️ Executive Summary
During the EKS cluster deployment with Terraform, the CoreDNS add-on entered a DEGRADED state and timed out. 
This issue occurred because no worker nodes were available to host the CoreDNS pods when using Auto Mode. 
By introducing a small Managed Node Group, extending the Terraform timeout for add-ons, and enabling conflict resolution, 
the cluster successfully stabilized, allowing all system add-ons to reach an ACTIVE state.

---

## 📌 Overview
During the provisioning of the **EKS cluster (todo-eks)** via Terraform, the deployment failed at the stage where **CoreDNS** was being created as an Amazon EKS managed add-on.  
Terraform reported the following error:

```
Error: waiting for EKS Add-On (todo-eks:coredns) create: timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)
```

This report documents the **root cause**, **troubleshooting process**, **solutions implemented**, and **key takeaways** from resolving the issue.

---

## ⚙️ Initial Setup
The environment was provisioned fully using **Terraform** with the following structure:

| Component | Description |
|------------|--------------|
| **VPC** | Custom CIDR (10.77.0.0/16) with private/public subnets, tagged for EKS |
| **EKS Module** | `terraform-aws-modules/eks/aws` v21 |
| **VPC Module** | `terraform-aws-modules/vpc/aws` v6.4.0 |
| **Compute Mode** | Auto Mode (`compute_config = { enabled = true }`) |
| **Kubernetes Add-ons** | CoreDNS, VPC-CNI, kube-proxy |
| **Terraform Version** | 1.6.x |
| **AWS Region** | eu-west-1 |

---

## ❌ Problem Description
Terraform was able to create:
- the **EKS control plane**,  
- the **VPC**, and  
- the **subnets and tags**,  

…but failed to successfully initialize the **CoreDNS add-on**.  

The error message showed:
```
waiting for EKS Add-On (todo-eks:coredns) create: timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED')
```

---

## 🧩 Root Cause Analysis
The CoreDNS add-on runs as **Pods** within the `kube-system` namespace.

EKS **Auto Mode** dynamically provisions nodes **only when workloads are scheduled**.  
However, CoreDNS is itself a **workload** that must start immediately for the cluster to function.

This creates a **circular dependency**:
> CoreDNS needs a Node to start,  
> but Auto Mode waits for a Pod to request a Node.

Therefore, CoreDNS could not be scheduled and stayed in a **DEGRADED** state indefinitely.

---

## 🧠 Diagnostic Steps
1. **Verified EKS cluster creation**
   ```bash
   aws eks list-clusters --region eu-west-1
   ```

2. **Checked nodes**
   ```bash
   kubectl get nodes
   ```
   → Result: no nodes available.

3. **Checked CoreDNS status**
   ```bash
   kubectl -n kube-system get pods
   ```
   → CoreDNS pods pending; no nodes to schedule on.

4. **Reviewed Terraform output**
   Terraform logs indicated that the add-on could not transition to `ACTIVE` because the deployment remained unscheduled.

---

## 🛠️ Solution Implemented
### 1️⃣ Added a **Managed Node Group (MNG)**
To ensure CoreDNS has compute capacity, a small node group was introduced:

```hcl
managed_node_groups = {
  baseline = {
    instance_types = ["t3.medium"]
    desired_size   = 1
    min_size       = 1
    max_size       = 2
  }
}
```

This guarantees at least one EC2 instance (Node) is always available.

---

### 2️⃣ Extended Timeout and Conflict Resolution for Add-ons
Amazon Q recommended adding configuration to prevent premature timeouts and version conflicts:

```hcl
addons = {
  coredns = {
    most_recent = true
    resolve_conflicts = "OVERWRITE"
    timeouts = {
      create = "30m"
      update = "30m"
    }
  }
  vpc-cni   = { most_recent = true, resolve_conflicts = "OVERWRITE" }
  kube-proxy= { most_recent = true, resolve_conflicts = "OVERWRITE" }
}
```

#### 🔍 Explanation
- `most_recent = true` → Ensures the latest compatible version of the add-on is deployed.
- `resolve_conflicts = "OVERWRITE"` → Prevents Terraform from deleting and recreating add-ons when minor version mismatches occur.
- `timeouts` → Extends the default waiting period from 20m to 30m, giving EKS time to stabilize.

---

### 3️⃣ Re-applied Terraform
After the changes:
```bash
cd infra/terraform
terraform init -upgrade
terraform apply -auto-approve
```

Terraform successfully created the EKS add-ons without further timeout errors.

---

## ✅ Verification
1. **Cluster status**
   ```bash
   kubectl cluster-info
   ```
2. **Nodes**
   ```bash
   kubectl get nodes
   ```
   → At least one node showed as `Ready`.
3. **CoreDNS pods**
   ```bash
   kubectl -n kube-system get pods -l k8s-app=kube-dns
   ```
   → Pods were in `Running` state.

Result:  
`CoreDNS`, `kube-proxy`, and `vpc-cni` all reached **ACTIVE** status.

---

## 🔍 Lessons Learned
| Area | Key Insight |
|------|--------------|
| **Nodes** | Kubernetes Pods always require Nodes to run. Auto Mode may cause delays for system Pods like CoreDNS. |
| **Managed Node Group** | A single small node group ensures cluster stability during bootstrapping. |
| **Add-on Management** | Using `resolve_conflicts` and `timeouts` prevents unnecessary recreation and timeout errors. |
| **Terraform Module Versions** | Version mismatches can remove or rename arguments. Always verify against module docs (e.g., v21 for EKS, v6.4.0 for VPC). |
| **Observability** | `kubectl get pods -A` and `kubectl get nodes` are the simplest, fastest ways to diagnose cluster health. |

---

## 🧱 Current Architecture After Fix
```
AWS EKS Cluster (todo-eks)
│
├─ VPC (10.77.0.0/16)
│   ├─ Public Subnets → Tagged "role/elb"
│   └─ Private Subnets → Tagged "role/internal-elb"
│
├─ Managed Node Group (t3.medium x1)
│   ├─ CoreDNS Pod
│   ├─ kube-proxy Pod
│   ├─ vpc-cni Pod
│   └─ Ready to schedule application Pods
│
└─ Add-ons (ACTIVE)
    ├─ CoreDNS
    ├─ VPC-CNI
    └─ Kube-proxy
```

---

## 🚀 Next Steps
- Verify app workloads (MongoDB, backend, frontend) deploy correctly under the new node group.
- Integrate Helm and Argo CD for CI/CD automation.
- Optionally scale down the baseline MNG once Auto Mode becomes stable.

---

## 🏁 Summary
The **CoreDNS DEGRADED** issue was caused by the absence of worker nodes when using **EKS Auto Mode**.  
By introducing a **small Managed Node Group**, extending add-on **timeouts**, and resolving **version conflicts**, the EKS cluster became stable and fully operational.  
This approach ensures reliable provisioning and reproducible deployments in a purely Infrastructure-as-Code workflow.
