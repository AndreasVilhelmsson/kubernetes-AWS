# EKS Todo App Deployment - Issues & Solutions Report

## Summary
This document details all issues encountered during the deployment and update of the React/TypeScript todo application to AWS EKS, and their resolutions.

---

## Issue 1: GitHub Actions Not Building New Images

### Problem
After updating the application code (React components, SASS, TypeScript), the changes were not reflected in EKS even after running `kubectl rollout restart`.

### Root Cause
The updated frontend code was not committed and pushed to GitHub, so GitHub Actions never built new Docker images with the changes.

### Solution
```bash
git add app/todo-frontend/
git commit -m "Add complete todo UI with React components and SASS"
git push
```

Then wait for GitHub Actions to build images and restart deployments:
```bash
kubectl rollout restart deployment -n eks-mongo-todo todo-frontend
kubectl rollout restart deployment -n eks-mongo-todo todo-backend
```

### Impact
Medium - Required manual intervention to push code and restart pods.

---

## Issue 2: Pods Stuck in Pending State - "Too Many Pods"

### Problem
```
Warning  FailedScheduling  0/1 nodes are available: 1 Too many pods. 
preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
```

New pods could not be scheduled after rollout restart.

### Root Cause
Single t3.small node was at capacity. With system pods (aws-node, coredns, ebs-csi-controller, ebs-csi-node, kube-proxy, ingress-nginx-controller) plus application pods (mongodb, backend, frontend), the node had no capacity for new pods during rolling updates.

### Solution
Increased node count from 1 to 2:

**variables.tf:**
```hcl
variable "node_min" {
  default = 2  # Changed from 1
}

variable "node_max" {
  default = 2  # Changed from 1
}
```

However, EKS wouldn't allow updating min_size to 2 when desired_size was still 1.

**Multi-step fix:**
```bash
# Step 1: Increase max_size first
aws eks update-nodegroup-config \
  --cluster-name todo-eks \
  --nodegroup-name default-20251024133948907400000010 \
  --scaling-config maxSize=2

# Step 2: Increase desired_size
aws eks update-nodegroup-config \
  --cluster-name todo-eks \
  --nodegroup-name default-20251024133948907400000010 \
  --scaling-config desiredSize=2

# Step 3: Run terraform apply to sync state
terraform apply
```

### Impact
High - Blocked deployment until resolved. Required manual AWS CLI commands.

---

## Issue 3: Network Timeout Between Nodes

### Problem
```
2025/10/26 10:30:22 [error] upstream timed out (110: Operation timed out) 
while connecting to upstream, client: 10.0.2.19, server: _, 
request: "GET / HTTP/1.1", upstream: "http://10.0.1.71:80/"
```

Ingress controller (on node 1) could not reach frontend pod (on node 2). All requests resulted in 504 Gateway Timeout.

### Root Cause
With 2 nodes, pods were distributed across both nodes. The node security group did not have a rule allowing traffic between nodes in the same security group. By default, EKS only allows specific ports (kubelet, coredns, etc.) but not all traffic.

### Solution
Added security group rule to allow all traffic between nodes:

```bash
# Find node security group ID
terraform state show 'module.eks.aws_security_group.node[0]' | grep "id "
# Output: sg-088f8e66e28c67fb2

# Add self-referencing rule
aws ec2 authorize-security-group-ingress \
  --group-id sg-088f8e66e28c67fb2 \
  --protocol all \
  --source-group sg-088f8e66e28c67fb2
```

This allows any pod on any node to communicate with any other pod on any node.

### Impact
Critical - Application was completely non-functional until resolved. Required AWS CLI security group modification.

---

## Issue 4: Ingress Path Rewrite Breaking API Calls

### Problem
```
GET /api/health -> 404 Not Found
GET /api/todos -> 404 Not Found
```

All API calls returned 404 even though backend pod was running and healthy.

### Root Cause
Ingress configuration had a rewrite rule that stripped the `/api` prefix:

**Original (broken):**
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
  rules:
    - http:
        paths:
          - path: /api(/|$)(.*)
            pathType: Prefix
            backend: { service: { name: todo-backend, port: { number: 80 } } }
```

This regex captured everything after `/api/` and rewrote the path. So:
- `/api/health` → `/health` (404, backend expects `/api/health`)
- `/api/todos` → `/todos` (404, backend expects `/api/todos`)

### Solution
Removed the rewrite rule and simplified paths:

**Fixed:**
```yaml
annotations:
  # Removed: nginx.ingress.kubernetes.io/rewrite-target: /$1
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend: { service: { name: todo-backend, port: { number: 80 } } }
          - path: /
            pathType: Prefix
            backend: { service: { name: todo-frontend, port: { number: 80 } } }
```

Applied with:
```bash
kubectl apply -f k8s/ingress/todo-ingress.yaml
```

### Impact
Critical - API was completely broken. Frontend loaded but couldn't fetch data.

---

## Issue 5: SASS Import Deprecation Warnings

### Problem
```
Deprecation Warning [import]: Sass @import rules are deprecated 
and will be removed in Dart Sass 3.0.0.
```

### Root Cause
Using old `@import` syntax instead of modern `@use` syntax in SASS files.

### Solution
Updated all SASS files to use `@use` with namespace:

**Before:**
```scss
@import '../styles/variables';
```

**After:**
```scss
@use '../styles/variables' as *;
```

### Impact
Low - Just warnings, but fixed for future compatibility.

---

## Issue 6: TypeScript verbatimModuleSyntax Errors

### Problem
```
[ts] 'Todo' is a type and must be imported using a type-only import 
when 'verbatimModuleSyntax' is enabled.
```

### Root Cause
TypeScript strict mode requires type-only imports to be explicitly marked with `import type`.

### Solution
Updated all type imports:

**Before:**
```typescript
import { Todo } from '../services/todoService';
import { FormEvent } from 'react';
```

**After:**
```typescript
import type { Todo } from '../services/todoService';
import type { FormEvent } from 'react';
```

### Impact
Low - TypeScript compilation errors, easy fix.

---

## Issue 7: Array Filter Error on Initial Load

### Problem
```
Uncaught TypeError: todos.filter is not a function
```

### Root Cause
Initial state or API response was not an array. Components tried to call `.filter()` on undefined or non-array value.

### Solution
Added array checks in components:

**TodoStats.tsx:**
```typescript
const active = Array.isArray(todos) ? todos.filter(t => !t.completed).length : 0;
const completed = Array.isArray(todos) ? todos.filter(t => t.completed).length : 0;
```

**TodoList.tsx:**
```typescript
if (!Array.isArray(todos) || todos.length === 0) {
  return <div className="todo-list__empty">No todos yet. Add one above! 🎉</div>;
}
```

**todoService.ts:**
```typescript
getAll: async (): Promise<Todo[]> => {
  const response = await axios.get<Todo[]>(`${API_BASE}/todos`);
  return response.data || [];  // Fallback to empty array
}
```

### Impact
Medium - Application crashed on load until fixed.

---

## Lessons Learned

### 1. Multi-Node Networking Requires Security Group Configuration
When scaling from 1 to 2+ nodes, ensure node security groups allow inter-node communication. EKS doesn't do this by default.

**Best Practice:**
```bash
# Add this rule during cluster setup
aws ec2 authorize-security-group-ingress \
  --group-id <node-sg> \
  --protocol all \
  --source-group <node-sg>
```

### 2. Ingress Path Rewriting is Tricky
Avoid complex regex rewrites unless absolutely necessary. Simple prefix matching is more reliable:
- Use `/api` with `Prefix` pathType
- Let backend handle full paths including `/api` prefix

### 3. Node Capacity Planning
t3.small nodes can only fit ~10-15 pods depending on resource requests. Plan for:
- System pods: 6-8 (aws-node, coredns, ebs-csi, kube-proxy, etc.)
- Application pods: 3-5
- Rolling update overhead: 2x application pods during updates

**Recommendation:** Use at least 2 nodes for production to handle rolling updates.

### 4. GitHub Actions Workflow
Changes only deploy when:
1. Code is committed and pushed
2. GitHub Actions builds new images
3. Pods are restarted with `kubectl rollout restart`

**Alternative:** Use image tags with versions instead of `:latest` to force updates.

### 5. TypeScript Strict Mode
Modern TypeScript requires:
- `import type` for type-only imports
- Proper type guards for array operations
- Explicit type annotations

### 6. Defensive Programming
Always check if data is an array before calling array methods:
```typescript
if (!Array.isArray(data)) return [];
```

---

## Architecture Overview

### Final Working Setup

**Infrastructure:**
- VPC with public subnets (no NAT Gateway for cost savings)
- EKS cluster with 2 t3.small spot instances
- Node security group allowing all inter-node traffic
- EBS CSI driver with IAM role for persistent storage

**Application:**
- MongoDB StatefulSet with 5Gi persistent volume
- Backend: .NET 9 API with MongoDB driver
- Frontend: React + TypeScript + SASS + Axios
- Ingress: NGINX Ingress Controller with NLB

**Networking:**
```
Internet → NLB → Ingress Controller → Services → Pods
                     ↓
                  /api → backend:80 → backend-pod:8080
                  /    → frontend:80 → frontend-pod:80
```

### Cost Breakdown
- EKS Control Plane: ~$73/month
- 2x t3.small spot: ~$10/month
- EBS gp3 5GB: ~$0.40/month
- NLB: ~$16/month
- **Total: ~$100/month**

---

## Time Investment
- Initial deployment: 2 hours
- Troubleshooting node capacity: 30 minutes
- Fixing security groups: 45 minutes
- Debugging Ingress paths: 1 hour
- Code fixes (TypeScript, SASS): 30 minutes
- **Total: ~4.75 hours**

---

## Success Metrics
- ✅ Application fully functional on EKS
- ✅ MongoDB data persists across pod restarts
- ✅ Frontend and backend communicate correctly
- ✅ Ingress routes traffic properly
- ✅ Multi-node setup working
- ✅ GitHub Actions CI/CD pipeline functional
- ✅ Clean TypeScript code with proper types
- ✅ Modern SASS with @use syntax
