# Conversation Summary - EKS MongoDB Todo Project

## Projektöversikt
Fullständig deployment av en todo-applikation på AWS EKS med MongoDB, inklusive infrastruktur, applikationsutveckling, CI/CD och dokumentation.

## Terraform Configuration Fixes
- **VPC-konfiguration**: Fixade typos i vpc.tf (vpc_deor → vpc_cidr, gats → tags)
- **DNS-attribut**: Tog bort enable_dns64 (ej supporterat)
- **Versionskonflikt**: Löste AWS provider konflikt genom att nedgradera EKS module till v19 och VPC module till v5
- **Provider-kompatibilitet**: AWS provider ~> 5.0 fungerar med EKS v19 och VPC v5

## Helm Provider Configuration
- **Syntaxproblem**: Testade både v2 och v3 syntax för Helm provider
- **Lösning**: Tom helm provider block som ärver konfiguration från kubernetes provider
- **Resultat**: Fungerar för att deploya ingress-nginx via Helm

## EKS Deployment Issues
- **VPC och EKS**: Lyckad deployment efter att ha löst provider-versioner
- **EBS CSI timeout**: Fixade genom att lägga till IAM role med IRSA (IAM Roles for Service Accounts)
- **Addon-konfiguration**: EBS CSI driver krävs för persistent volumes i EKS

## MongoDB YAML Splitting
- **Problem**: Multi-document YAML fungerar inte med Terraform yamldecode
- **Lösning**: Splittade MongoDB YAML i separata filer:
  - `service.yaml` - Headless service för StatefulSet
  - `statefulset.yaml` - MongoDB StatefulSet med PVC

## React Todo App Development
- **Stack**: React, TypeScript, SASS, Axios
- **Struktur**: Komponentbaserad arkitektur med services layer
- **Komponenter**: TodoForm, TodoItem, TodoList, TodoStats
- **API-integration**: todoService.ts med CRUD-operationer
- **Styling**: SASS med variables, mixins och responsiv design

## SASS and TypeScript Fixes
- **SASS-migration**: Uppdaterade från @import till @use syntax (modern SASS)
- **TypeScript-typer**: Fixade type imports med `import type` syntax för verbatimModuleSyntax
- **Kompilering**: Löste alla build errors för både frontend och backend

## Deployment to EKS
- **GitHub**: Pushade kod till repository
- **GitHub Actions**: Automatiska builds triggades för backend och frontend
- **Container Registry**: Images pushades till GitHub Container Registry
- **EKS Deployment**: Terraform applicerade Kubernetes manifests
- **Verifiering**: Applikation tillgänglig via Load Balancer URL

## Node Scaling Issues
- **Problem**: "Too many pods" error på single t3.small node
- **Root cause**: En node kan inte köra alla pods (frontend, backend, MongoDB, system pods)
- **Lösning**: Skalade till 2 nodes via AWS CLI:
  1. Uppdatera maxSize till 2
  2. Uppdatera desiredSize till 2
  3. Uppdatera minSize till 2
- **Resultat**: Pods distribuerade över två nodes, alla running

## Inter-Node Networking
- **Problem**: 504 Gateway Timeout mellan pods på olika nodes
- **Root cause**: Security group blockerade trafik mellan nodes
- **Lösning**: Lade till security group rule som tillåter all trafik från samma security group
- **Command**: `aws ec2 authorize-security-group-ingress --group-id <sg-id> --source-group <sg-id> --protocol all`
- **Resultat**: Pods kan kommunicera över node-gränser

## Ingress Path Rewriting
- **Problem**: 404 errors på API-anrop trots korrekt routing
- **Root cause**: nginx.ingress.kubernetes.io/rewrite-target annotation skrev om paths felaktigt
- **Lösning**: 
  - Tog bort rewrite-target annotation
  - Ändrade från regex path matching till simple prefix
  - Backend lyssnar på `/api/*` direkt
- **Resultat**: API-anrop fungerar korrekt

## Final Report Creation
Skapade omfattande 4-delad Kubernetes deployment rapport:

### Del 1: Kubernetes Fundamentals
- Control Plane komponenter (API Server, etcd, Scheduler, Controller Manager)
- Worker Node komponenter (kubelet, kube-proxy, container runtime)
- Add-ons (CoreDNS, EBS CSI, NGINX Ingress)
- Kubernetes objects (Namespace, Pod, Deployment, StatefulSet, Service, Ingress)

### Del 2: Administration
- ConfigMap/Secret för konfiguration
- PV/PVC/StorageClass för persistent storage
- Lokal cluster administration (Minikube, Kind, Docker Desktop)
- AWS EKS administration (CLI och Terraform)
- kubectl commands och debugging

### Del 3: Application Design & Security
- Applikationsarkitektur (frontend, backend, databas)
- Kubernetes manifest definitions
- Omfattande säkerhetsdesign:
  - Nätverkssäkerhet (VPC, Security Groups)
  - IAM/RBAC med IRSA
  - Secrets management
  - Container security
  - Data encryption

### Del 4: CI/CD & Operations
- GitHub Actions workflows
- Infrastructure as Code deployment
- Application update procedures
- Monitoring och logging
- Kostnadsanalys (~$100/månad)
- Challenges och solutions
- Appendix med screenshot-guide och Cloudcraft-instruktioner

## Filer och Konfiguration

### Infrastructure (Terraform)
- **vpc.tf**: VPC module v5.0, public/private subnets, EKS/ELB tags
- **eks.tf**: EKS cluster v19.0, 2x t3.small spot instances, version 1.29
- **versions.tf**: Terraform >= 1.5.0, AWS ~> 5.0, Kubernetes >= 2.26.0, Helm ~> 2.12
- **providers-k8s.tf**: Kubernetes och Helm providers med EKS auth
- **addons-ingress.tf**: EBS CSI addon med IRSA, ingress-nginx (manuellt installerad)
- **apply-k8s.tf**: Kubernetes manifests för alla komponenter
- **variables.tf**: node_min=2, node_max=2, enable_nat_gateway=false, use_spot=true

### Kubernetes Manifests
- **k8s/mongo/statefulset.yaml**: MongoDB StatefulSet, 1 replica, 5Gi EBS gp3
- **k8s/mongo/service.yaml**: Headless service för StatefulSet
- **k8s/backend/deploy.yaml**: Backend deployment, MONGO_URI env var
- **k8s/frontend/deploy.yaml**: Frontend deployment
- **k8s/ingress/todo-ingress.yaml**: Simple prefix paths, timeout annotations

### Application Code
- **app/todo-frontend/src/App.tsx**: Main component (50 lines), använder TodoForm, TodoStats, TodoList
- **app/todo-frontend/src/services/todoService.ts**: API service med CRUD methods
- **app/todo-frontend/src/components/**: TodoForm, TodoItem, TodoList, TodoStats med SCSS
- **app/todo-frontend/src/styles/_variables.scss**: SASS variables för colors, spacing, etc.
- **app/todo-backend/Program.cs**: .NET 9 minimal API, MongoDB integration, CORS
- **app/todo-backend/todo-backend.csproj**: MongoDB.Driver v2.29.0

### Documentation
- **docs/SOLUTION.md**: Final working configuration, architecture, key decisions
- **docs/FAILURE_REPORT.md**: 13 issues med root causes och solutions
- **docs/DEPLOYMENT_ISSUES_REPORT.md**: Comprehensive deployment issues report
- **docs/KUBERNETES_RAPPORT_DEL1-4.md**: Four-part Kubernetes report för kursuppgift

## Key Insights

### Tekniska Insikter
- **Kostnadsoptimering**: Spot instances, no NAT gateway, single NLB, t3.small nodes
- **Two-phase deployment**: Först infrastructure only, sedan uncomment providers och deploy apps
- **Version compatibility**: EKS v20 kräver AWS provider v6, men VPC v6 också kräver v6 → downgrade till v19/v5
- **Multi-node networking**: Kräver explicit security group rule för inter-node traffic
- **Ingress routing**: Simple prefix matching mer reliable än regex rewriting
- **GitHub Actions**: Automatiska builds vid push, taggade med run number och :latest
- **Rolling updates**: `kubectl rollout restart` för att uppdatera pods med latest images

### Kostnadsanalys
- **EKS Control Plane**: $73/månad
- **2x t3.small spot**: ~$10/månad
- **EBS volumes**: $0.40/månad
- **Network Load Balancer**: $16/månad
- **Total**: ~$100/månad

### Applikationsstatus
- **URL**: a1f7bd2843e884023a494330309d7a81-807945157.eu-west-1.elb.amazonaws.com
- **Status**: Fully functional
- **Frontend**: React SPA med todo-funktionalitet
- **Backend**: .NET API med MongoDB integration
- **Database**: MongoDB StatefulSet med persistent storage

## Projektstruktur
```
eks-mongo-todo/
├── app/
│   ├── todo-backend/          # .NET 9 API
│   └── todo-frontend/         # React TypeScript app
├── infra/
│   └── terraform/             # Infrastructure as Code
├── k8s/
│   ├── backend/               # Backend manifests
│   ├── frontend/              # Frontend manifests
│   ├── ingress/               # Ingress configuration
│   └── mongo/                 # MongoDB StatefulSet
├── .github/
│   └── workflows/             # CI/CD pipelines
└── docs/                      # Dokumentation
```

## Nästa Steg för Användaren
1. Sammanfoga 4 markdown-filer till ett dokument
2. Ta AWS Console screenshots enligt Appendix B
3. Skapa Cloudcraft arkitekturdiagram enligt Appendix A
4. Infoga bilder där **[BILD: ...]** placeholders finns
5. Konvertera markdown till PDF med pandoc eller VS Code extension
6. Lägg till försättsblad med namn, kurs, Git repo och sammanfattning
