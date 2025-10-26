# Kubernetes-rapport – EKS Todo-applikation (IaC)

**Namn:** Andreas Vilhelmsson  
**Kurs:** Kubernetes  
**GitHub-repo:** https://github.com/AndreasVilhelmsson/kubernetes-AWS

---

## Sammanfattning
Den här rapporten beskriver ett komplett, återupprepningsbart Kubernetes-flöde på AWS EKS för en Todo-applikation bestående av **React (frontend)**, **.NET 9 (backend)** och **MongoDB**. Klustret och nätverk skapas med **Terraform (IaC)**, containrar byggs och publiceras med **GitHub Actions** till **GitHub Container Registry (GHCR)**, och deployment till Kubernetes sker med manifest/Helm (med ett dedikerat **namespace** och konsekventa **tags** på resurserna). Fokus har varit **låg kostnad (student-lab)**, möjlighet att **riva upp och ner** utan manuell påverkan, samt **portabilitet** mellan ARM64 (lokal Mac) och AMD64 (EKS noder) genom multi-arch images.

---


## Innehåll
1. [Fundament i ett Kubernetes-kluster](#fundament-i-ett-kubernetes-kluster)
2. [Vanliga Kubernetes-objekt (kind:)](#vanliga-kubernetes-objekt-kind)
3. [Administration lokalt och i molnet](#administration-lokalt-och-i-molnet)
4. [Egen applikation på EKS](#egen-applikation-på-eks)
   - [Design & arkitektur](#design--arkitektur)
   - [IaC: Terraform för VPC + EKS](#iac-terraform-för-vpc--eks)
   - [Containrar & CI/CD (GitHub Actions till GHCR)](#containrar--cicd-github-actions-till-ghcr)
   - [Kubernetes-manifest/Helm](#kubernetes-manifesthelm)
   - [Säkerhet](#säkerhet)
   - [Driftsättning & test](#driftsättning--test)
5. [Arkitekturdiagram (Mermaid)](#arkitekturdiagram-mermaid)
6. [Skärmdumpar](#skärmdumpar)
7. [Lärdomar och fallgropar](#lärdomar-och-fallgropar)
8. [Referenser](#referenser)

---


## Fundament i ett Kubernetes-kluster

# Kubernetes Deployment - Todo Application
## Inlämningsuppgift Cloud Services

---

**Namn:** Andreas Vilhelmsson  
**Kurs:** Cloud Services  
**Git Repository:** https://github.com/andreasvilhelmsson/eks-mongo-todo  
**Datum:** Oktober 2025

---

## Sammanfattning

Detta projekt demonstrerar deployment av en fullstack todo-applikation till AWS EKS (Elastic Kubernetes Service). Applikationen består av en React/TypeScript frontend, .NET backend API, och MongoDB databas. Projektet omfattar infrastruktur som kod med Terraform, CI/CD med GitHub Actions, och Kubernetes-manifest för orchestrering.

**Teknologier:**
- Kubernetes (AWS EKS)
- Docker & Container Registry (GitHub Container Registry)
- Terraform (Infrastructure as Code)
- React + TypeScript + SASS (Frontend)
- .NET 9 (Backend API)
- MongoDB (Database)
- NGINX Ingress Controller
- AWS VPC, EBS, NLB

---

## 1. Kubernetes Kluster - Fundamentala Komponenter

Ett Kubernetes-kluster består av två huvudsakliga delar: **Control Plane** och **Worker Nodes**.

### 1.1 Control Plane Komponenter

![AWS EKS-klusteröversikt för todo-eks](images/Cluster-overview.jpg)
*AWS EKS Console visar klustret `todo-eks` med status, version och endpoint.*

#### API Server (kube-apiserver)
- **Funktion:** Klustrets frontend och centrala kommunikationspunkt
- **Ansvar:** 
  - Exponerar Kubernetes API
  - Validerar och processar REST-requests
  - Uppdaterar etcd med kluster-state
- **I praktiken:** Alla kubectl-kommandon kommunicerar med API Server

#### etcd
- **Funktion:** Distribuerad key-value databas
- **Ansvar:**
  - Lagrar all kluster-konfiguration och state
  - Backup och restore-punkt för klustret
- **I praktiken:** Innehåller alla Deployments, Services, ConfigMaps, etc.

#### Scheduler (kube-scheduler)
- **Funktion:** Beslutar vilken node en pod ska köras på
- **Ansvar:**
  - Analyserar resource requirements (CPU, minne)
  - Kontrollerar node constraints och affinity rules
  - Tilldelar pods till lämpliga nodes
- **I praktiken:** När du skapar en Deployment, väljer Scheduler vilken node som får köra poden

#### Controller Manager (kube-controller-manager)
- **Funktion:** Kör olika controllers som övervakar kluster-state
- **Ansvar:**
  - Node Controller: Övervakar node-hälsa
  - Replication Controller: Säkerställer rätt antal pod-replicas
  - Endpoints Controller: Populerar Endpoints-objekt
  - Service Account Controller: Skapar default service accounts
- **I praktiken:** Om en pod kraschar, upptäcker Controller Manager detta och skapar en ny

#### Cloud Controller Manager
- **Funktion:** Integrerar med cloud provider (AWS i vårt fall)
- **Ansvar:**
  - Node Controller: Kontrollerar om nodes har tagits bort i cloud
  - Route Controller: Sätter upp routes i cloud infrastructure
  - Service Controller: Skapar/uppdaterar cloud load balancers
- **I praktiken:** När vi skapar en Service type=LoadBalancer, skapar Cloud Controller Manager en AWS NLB

### 1.2 Worker Node Komponenter

![AWS EC2 worker nodes för EKS-klustret](images/Cluster-nodes.jpg)
*EC2 Console visar de två t3.small worker nodes och tillhörande taggar.*

#### kubelet
- **Funktion:** Agent som körs på varje node
- **Ansvar:**
  - Tar emot PodSpecs från API Server
  - Säkerställer att containers körs och är healthy
  - Rapporterar node och pod status tillbaka till API Server
- **I praktiken:** Startar och övervakar Docker containers på noden

#### kube-proxy
- **Funktion:** Nätverksproxy på varje node
- **Ansvar:**
  - Implementerar Kubernetes Service-koncept
  - Hanterar network rules (iptables/IPVS)
  - Möjliggör load balancing mellan pods
- **I praktiken:** När du anropar en Service, routar kube-proxy trafiken till rätt pod

#### Container Runtime
- **Funktion:** Kör containers
- **Ansvar:**
  - Pullar container images
  - Startar och stoppar containers
  - Hanterar container lifecycle
- **I praktiken:** Docker, containerd, eller CRI-O som faktiskt kör applikationerna

### 1.3 Add-ons i vårt kluster

#### CoreDNS
- **Funktion:** DNS-server för klustret
- **Ansvar:** Service discovery - översätter service-namn till IP-adresser
- **I praktiken:** Backend kan nå MongoDB via `mongodb:27017` istället för IP

#### AWS EBS CSI Driver
- **Funktion:** Container Storage Interface för AWS EBS
- **Ansvar:** 
  - Dynamisk provisioning av EBS volumes
  - Attach/detach volumes till nodes
  - Snapshot och restore
- **I praktiken:** MongoDB använder EBS CSI för persistent storage (5Gi gp3 volume)

#### NGINX Ingress Controller
- **Funktion:** Ingress controller för HTTP/HTTPS routing
- **Ansvar:**
  - Exponerar Services externt via Load Balancer
  - HTTP routing baserat på host/path
  - SSL/TLS termination
- **I praktiken:** Routar `/api/*` till backend och `/` till frontend

---

## 2. Kubernetes Objekt (kind:) - Typer och Användning

### 2.1 Namespace

**Funktion:** Logisk isolering av resurser inom klustret

**Användning:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: eks-mongo-todo
  labels:
    app.kubernetes.io/managed-by: terraform
    project: eks-mongo-todo
```

**I vårt projekt:**
- Alla applikationsresurser ligger i namespace `eks-mongo-todo`
- Separerar vår app från system-pods (kube-system, ingress-nginx)
- Möjliggör resource quotas och RBAC per namespace

**Relation:** Namespace är överst i hierarkin - alla andra objekt tillhör ett namespace

---

### 2.2 Pod

**Funktion:** Minsta deployerbara enheten - en eller flera containers som delar nätverk och storage

**Användning:**
Pods skapas vanligtvis inte direkt, utan via Deployments eller StatefulSets.

**I vårt projekt:**
```bash
kubectl get pods -n eks-mongo-todo
NAME                             READY   STATUS
mongodb-0                        1/1     Running
todo-backend-55d96ff964-2wj6k    1/1     Running
todo-frontend-5f5b6987d7-rwf5r   1/1     Running
```

**Relation:** 
- Skapas av Deployment/StatefulSet
- Exponeras av Service
- Scheduleras på Node av Scheduler

---

### 2.3 Deployment

**Funktion:** Deklarativ hantering av Pods och ReplicaSets - för stateless applikationer

**Användning:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-backend
  namespace: eks-mongo-todo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todo-backend
  template:
    metadata:
      labels:
        app: todo-backend
    spec:
      containers:
      - name: api
        image: ghcr.io/andreasvilhelmsson/todo-backend-v2:latest
        ports:
        - containerPort: 8080
        env:
        - name: MONGO_URI
          value: mongodb://root:changeme@mongodb:27017/?authSource=admin
```

**Fördelar:**
- Rolling updates utan downtime
- Rollback till tidigare version
- Self-healing - återskapar pods vid failure
- Scaling - enkelt öka/minska replicas

**I vårt projekt:**
- Backend Deployment: 1 replica av .NET API
- Frontend Deployment: 1 replica av React app

**Relation:**
- Skapar och hanterar ReplicaSet
- ReplicaSet skapar och hanterar Pods
- Service pekar på Pods via labels

---

### 2.4 StatefulSet

**Funktion:** Hantering av stateful applikationer med persistent identity och storage

**Användning:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: eks-mongo-todo
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongo
        image: mongo:7
        ports:
        - containerPort: 27017
        volumeMounts:
        - name: data
          mountPath: /data/db
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-gp3
      resources:
        requests:
          storage: 5Gi
```

**Skillnad mot Deployment:**
- Stable network identity: `mongodb-0`, `mongodb-1`, etc.
- Persistent storage per pod
- Ordered deployment och scaling
- Ordered rolling updates

**I vårt projekt:**
- MongoDB StatefulSet med 1 replica
- Persistent volume på 5Gi EBS gp3
- Data överlever pod restarts

**Relation:**
- Skapar PersistentVolumeClaim per replica
- Service (headless) ger stable DNS namn
- Pods får ordnade namn: `<statefulset-name>-<ordinal>`

---

### 2.5 Service

**Funktion:** Abstraktion som exponerar Pods via ett stabilt nätverk endpoint

**Typer:**

#### ClusterIP (default)
Intern IP - endast tillgänglig inom klustret

```yaml
apiVersion: v1
kind: Service
metadata:
  name: todo-backend
  namespace: eks-mongo-todo
spec:
  selector:
    app: todo-backend
  ports:
  - port: 80
    targetPort: 8080
```

**I vårt projekt:**
- Backend Service: Exponerar backend pods på port 80
- Frontend Service: Exponerar frontend pods på port 80
- MongoDB Service: Headless service för StatefulSet

#### LoadBalancer
Exponerar Service externt via cloud load balancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  selector:
    app: ingress-nginx
  ports:
  - port: 80
    targetPort: 80
```

**I vårt projekt:**
- NGINX Ingress Controller använder LoadBalancer
- Skapar AWS Network Load Balancer automatiskt

**Relation:**
- Selector matchar Pod labels
- Endpoints-objekt skapas automatiskt med Pod IPs
- Ingress routar trafik till Services

---

### 2.6 Ingress

**Funktion:** HTTP/HTTPS routing till Services baserat på host och path

**Användning:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: todo-ingress
  namespace: eks-mongo-todo
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: todo-backend
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: todo-frontend
            port:
              number: 80
```

**Fördelar:**
- En Load Balancer för flera Services
- Path-based routing
- SSL/TLS termination
- URL rewriting

**I vårt projekt:**
- `/api/*` → backend Service
- `/*` → frontend Service
- Exponeras via AWS NLB

**Relation:**
- Kräver Ingress Controller (NGINX i vårt fall)
- Routar till Services (inte direkt till Pods)
- Ingress Controller skapar LoadBalancer Service



## Vanliga Kubernetes-objekt (kind:)

## 2.7 ConfigMap och Secret

### ConfigMap
**Funktion:** Lagra konfigurationsdata som key-value pairs

**Användning:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  API_URL: "http://backend:80"
  LOG_LEVEL: "info"
```

**I vårt projekt:**
- Används inte explicit, men environment variables i Deployments fyller samma syfte
- Bättre practice: Flytta MONGO_URI till ConfigMap

### Secret
**Funktion:** Lagra känslig data (lösenord, tokens, nycklar)

**Användning:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongo-credentials
type: Opaque
stringData:
  username: root
  password: changeme
```

**I vårt projekt:**
- MongoDB credentials hårdkodade i Deployment (ej production-ready)
- Bättre practice: Använd Secret och referera via secretKeyRef

**Relation:**
- Monteras som volumes eller environment variables i Pods
- Base64-encoded (inte krypterad!)
- För verklig säkerhet: AWS Secrets Manager eller HashiCorp Vault

---

### 2.8 PersistentVolume (PV) och PersistentVolumeClaim (PVC)

**Funktion:** Abstraktion för persistent storage

#### StorageClass
Definierar typer av storage som kan provisoneras dynamiskt

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
```

#### PersistentVolumeClaim
Request för storage från en Pod

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 5Gi
```

**I vårt projekt:**
- StatefulSet skapar automatiskt PVC via volumeClaimTemplates
- EBS CSI Driver provisonerar EBS volume dynamiskt
- MongoDB data persisteras på EBS gp3 volume

![EBS-volym kopplad till MongoDB StatefulSet](images/EBS-volumes.jpg)
*AWS EBS Console visar 5 GiB gp3-volym som används av MongoDB.*

![Detaljer för EBS-volymen inklusive kopplad pod](images/EBS-Volumes-details.jpg)
*Detaljvy med attachment till worker node och taggar från StatefulSet.*

**Relation:**
- StorageClass → PVC → PV → Pod
- CSI Driver hanterar lifecycle
- Volume följer Pod vid reschedule (samma node)

---

## 3. Administration av Kubernetes Kluster

### 3.1 Lokalt Kluster

#### Minikube
**Användning:**
```bash
# Starta lokalt kluster
minikube start --driver=docker --cpus=2 --memory=4096

# Deploya applikation
kubectl apply -f k8s/

# Exponera service lokalt
minikube service todo-frontend --url

# Stoppa kluster
minikube stop
```

**Fördelar:**
- Snabb utveckling och testning
- Ingen kostnad
- Fungerar på laptop

**Nackdelar:**
- Begränsade resurser
- Ingen cloud-integration
- Single-node

#### Kind (Kubernetes in Docker)
**Användning:**
```bash
# Skapa kluster
kind create cluster --name todo-dev

# Ladda lokala images
kind load docker-image todo-backend:latest --name todo-dev

# Ta bort kluster
kind delete cluster --name todo-dev
```

**Fördelar:**
- Multi-node kluster lokalt
- CI/CD testing
- Snabbare än Minikube

#### Docker Desktop Kubernetes
**Användning:**
- Aktivera i Docker Desktop settings
- Automatisk kubectl konfiguration
- Enklast för Mac/Windows användare

---

### 3.2 Molnbaserat Kluster (AWS EKS)

#### AWS EKS (Elastic Kubernetes Service)

**Fördelar:**
- Managed Control Plane (AWS hanterar master nodes)
- Integrerat med AWS services (IAM, VPC, EBS, ELB)
- Auto-scaling och auto-healing
- Production-ready

**Administration via AWS CLI:**

```bash
# Skapa kluster (manuellt)
aws eks create-cluster \
  --name todo-eks \
  --role-arn arn:aws:iam::123456789:role/eks-cluster-role \
  --resources-vpc-config subnetIds=subnet-xxx,subnet-yyy

# Konfigurera kubectl
aws eks update-kubeconfig --region eu-west-1 --name todo-eks

# Lista kluster
aws eks list-clusters

# Beskriva kluster
aws eks describe-cluster --name todo-eks
```

**Administration via Terraform (vårt projekt):**

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "todo-eks"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      capacity_type  = "SPOT"
      
      desired_size = 2
      min_size     = 2
      max_size     = 2
    }
  }
}
```

**Deployment workflow:**
```bash
# 1. Skapa infrastruktur
cd infra/terraform
terraform init
terraform apply

# 2. Konfigurera kubectl
aws eks update-kubeconfig --region eu-west-1 --name todo-eks

# 3. Verifiera anslutning
kubectl get nodes

# 4. Deploya applikation
kubectl apply -f k8s/
```

---

### 3.3 kubectl - Kommandoradsverktyg

**Grundläggande kommandon:**

```bash
# Visa resurser
kubectl get pods -n eks-mongo-todo
kubectl get services -n eks-mongo-todo
kubectl get deployments -n eks-mongo-todo

# Detaljerad information
kubectl describe pod mongodb-0 -n eks-mongo-todo
kubectl describe service todo-backend -n eks-mongo-todo

# Loggar
kubectl logs deployment/todo-backend -n eks-mongo-todo --tail=50
kubectl logs -f pod/mongodb-0 -n eks-mongo-todo  # Follow logs

# Exec into pod
kubectl exec -it mongodb-0 -n eks-mongo-todo -- mongosh

# Port forwarding (för lokal testning)
kubectl port-forward svc/todo-backend 8080:80 -n eks-mongo-todo

# Apply manifests
kubectl apply -f k8s/
kubectl apply -f k8s/backend/

# Delete resurser
kubectl delete deployment todo-backend -n eks-mongo-todo
kubectl delete -f k8s/

# Scaling
kubectl scale deployment todo-backend --replicas=3 -n eks-mongo-todo

# Rolling restart
kubectl rollout restart deployment/todo-backend -n eks-mongo-todo
kubectl rollout status deployment/todo-backend -n eks-mongo-todo
kubectl rollout undo deployment/todo-backend -n eks-mongo-todo

# Context management
kubectl config get-contexts
kubectl config use-context arn:aws:eks:eu-west-1:xxx:cluster/todo-eks
```

---

### 3.4 Monitoring och Debugging

**Kluster-hälsa:**
```bash
# Node status
kubectl get nodes
kubectl top nodes  # Kräver metrics-server

# Pod status
kubectl get pods --all-namespaces
kubectl top pods -n eks-mongo-todo

# Events
kubectl get events -n eks-mongo-todo --sort-by='.lastTimestamp'

# Cluster info
kubectl cluster-info
kubectl version
```

**Debugging:**
```bash
# Varför startar inte pod?
kubectl describe pod <pod-name> -n eks-mongo-todo

# Vanliga problem:
# - ImagePullBackOff: Image finns inte eller auth problem
# - CrashLoopBackOff: Container kraschar vid start
# - Pending: Ingen node har resurser
# - Error: Container exit code != 0

# Testa connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inne i pod:
wget -O- http://todo-backend/api/health
nslookup mongodb
```

## 4. Todo Application - Design och Deployment

### 4.1 Applikationsdesign

#### Arkitektur Overview

**Komponenter:**

1. **Frontend (React + TypeScript + SASS)**
   - Single Page Application
   - Axios för API-anrop
   - Komponentbaserad arkitektur
   - SASS variables för styling
   - Responsive design

2. **Backend (.NET 9 Web API)**
   - RESTful API
   - MongoDB.Driver för databas-access
   - CORS-konfiguration
   - Minimal API pattern

3. **Database (MongoDB 7)**
   - NoSQL document database
   - Persistent storage via EBS
   - StatefulSet för stable identity

**Dataflöde:**
```
User → Browser → NLB → Ingress Controller → Frontend Service → Frontend Pod
                                          ↓
                                    Backend Service → Backend Pod → MongoDB Service → MongoDB Pod
                                                                                    ↓
                                                                              EBS Volume (5Gi)
```

![Todo-appen körd via EKS och nådd via NLB](images/todo-app.jpg)
*Publikt NLB-endpoint presenterar React-frontenden med en aktiv uppgift.*

---

### 4.2 Applikationskod

#### Frontend Struktur
```
app/todo-frontend/
├── src/
│   ├── components/
│   │   ├── TodoForm.tsx       # Input form för nya todos
│   │   ├── TodoItem.tsx       # Enskild todo rad
│   │   ├── TodoList.tsx       # Lista av todos
│   │   └── TodoStats.tsx      # Statistik (active/completed)
│   ├── services/
│   │   └── todoService.ts     # API calls med Axios
│   ├── styles/
│   │   └── _variables.scss    # SASS variables
│   ├── App.tsx                # Main component
│   └── main.tsx               # Entry point
├── Dockerfile
└── nginx.conf                 # NGINX config för SPA routing
```

**Exempel - TodoService:**
```typescript
import axios from 'axios';

export type Todo = {
  id: string;
  title: string;
  completed: boolean;
  createdAt: string;
}

const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api';

export const todoService = {
  getAll: async (): Promise<Todo[]> => {
    const response = await axios.get<Todo[]>(`${API_BASE}/todos`);
    return response.data || [];
  },

  create: async (title: string): Promise<Todo> => {
    const response = await axios.post<Todo>(`${API_BASE}/todos`, { title });
    return response.data;
  },

  toggle: async (id: string, completed: boolean): Promise<void> => {
    await axios.put(`${API_BASE}/todos/${id}`, { completed: !completed });
  },

  delete: async (id: string): Promise<void> => {
    await axios.delete(`${API_BASE}/todos/${id}`);
  },
};
```

#### Backend Struktur
```
app/todo-backend/
├── Program.cs              # Main API file
├── todo-backend.csproj     # Project dependencies
└── Dockerfile
```

**Exempel - Backend API:**
```csharp
using MongoDB.Bson;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);

// CORS
builder.Services.AddCors(options => {
    options.AddDefaultPolicy(policy => {
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

// MongoDB
var mongoUri = builder.Configuration["MONGO_URI"] 
    ?? "mongodb://root:changeme@mongodb:27017/?authSource=admin";
var mongoClient = new MongoClient(mongoUri);
var database = mongoClient.GetDatabase("tododb");
var todosCollection = database.GetCollection<TodoItem>("todos");

builder.Services.AddSingleton(todosCollection);

var app = builder.Build();
app.UseCors();

// Endpoints
app.MapGet("/api/todos", async (IMongoCollection<TodoItem> collection) => {
    var todos = await collection.Find(_ => true).ToListAsync();
    return Results.Ok(todos);
});

app.MapPost("/api/todos", async (TodoCreateDto dto, 
    IMongoCollection<TodoItem> collection) => {
    var todo = new TodoItem {
        Title = dto.Title,
        Completed = false,
        CreatedAt = DateTime.UtcNow
    };
    await collection.InsertOneAsync(todo);
    return Results.Created($"/api/todos/{todo.Id}", todo);
});

app.Run();

record TodoCreateDto(string Title);
class TodoItem {
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public string? Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public bool Completed { get; set; }
    public DateTime CreatedAt { get; set; }
}
```



## Administration lokalt och i molnet

### 4.3 Kubernetes Manifest Definitioner

#### Namespace
```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: eks-mongo-todo
  labels:
    app.kubernetes.io/managed-by: terraform
    project: eks-mongo-todo
    owner: andreasvilhelmsson
    environment: dev
```

#### StorageClass
```yaml
# k8s/storageclass-ebs-gp3.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
```

**Förklaring:**
- `provisioner: ebs.csi.aws.com` - Använder AWS EBS CSI Driver
- `type: gp3` - Senaste generation EBS (billigare än gp2)
- `encrypted: "true"` - Krypterar data at rest
- `WaitForFirstConsumer` - Skapar volume i samma AZ som pod

---

#### MongoDB StatefulSet och Service

```yaml
# k8s/mongo/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: eks-mongo-todo
spec:
  clusterIP: None  # Headless service
  selector:
    app: mongodb
  ports:
  - port: 27017
```

```yaml
# k8s/mongo/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: eks-mongo-todo
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongo
        image: mongo:7
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: root
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: changeme
        ports:
        - containerPort: 27017
        volumeMounts:
        - name: data
          mountPath: /data/db
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-gp3
      resources:
        requests:
          storage: 5Gi
```

**Förklaring:**
- `clusterIP: None` - Headless service ger stable DNS: `mongodb-0.mongodb.eks-mongo-todo.svc.cluster.local`
- `volumeClaimTemplates` - Skapar automatiskt PVC för varje replica
- `ReadWriteOnce` - Volume kan bara mountas av en node åt gången
- StatefulSet garanterar ordnad start: `mongodb-0` först, sedan `mongodb-1`, etc.

---

#### Backend Deployment och Service

```yaml
# k8s/backend/svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: todo-backend
  namespace: eks-mongo-todo
spec:
  selector:
    app: todo-backend
  ports:
  - port: 80
    targetPort: 8080
```

```yaml
# k8s/backend/deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-backend
  namespace: eks-mongo-todo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todo-backend
  template:
    metadata:
      labels:
        app: todo-backend
    spec:
      containers:
      - name: api
        image: "%%IMAGE%%"  # Ersätts av Terraform
        ports:
        - containerPort: 8080
        env:
        - name: ASPNETCORE_URLS
          value: "http://+:8080"
        - name: MONGO_URI
          value: "mongodb://root:changeme@mongodb:27017/?authSource=admin"
```

**Förklaring:**
- Service exponerar port 80 externt, routar till pod port 8080
- `%%IMAGE%%` ersätts av Terraform med faktisk image URL
- `MONGO_URI` använder service name `mongodb` för DNS resolution
- Deployment skapar ReplicaSet som hanterar pods

---

#### Frontend Deployment och Service

```yaml
# k8s/frontend/svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: todo-frontend
  namespace: eks-mongo-todo
spec:
  selector:
    app: todo-frontend
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# k8s/frontend/deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-frontend
  namespace: eks-mongo-todo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todo-frontend
  template:
    metadata:
      labels:
        app: todo-frontend
    spec:
      containers:
      - name: web
        image: "%%IMAGE%%"
        ports:
        - containerPort: 80
```

**Förklaring:**
- NGINX serves static React build på port 80
- Ingen environment variables behövs (API URL är `/api` via Ingress)

---

#### Ingress

```yaml
# k8s/ingress/todo-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: todo-ingress
  namespace: eks-mongo-todo
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: todo-backend
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: todo-frontend
            port:
              number: 80
```

**Förklaring:**
- `ingressClassName: nginx` - Använder NGINX Ingress Controller
- Path-based routing: `/api/*` → backend, `/*` → frontend
- `Prefix` pathType matchar alla sub-paths
- Timeout annotations för långsamma API calls
- Ingen rewrite - paths skickas som de är till backend

![AWS console med Network Load Balancer för todo-eks](images/load-balancer.jpg)
*AWS Load Balancer Console visar NLB som skapats av Ingress Controller.*

---

### 4.4 Säkerhetsdesign

#### 4.4.1 Nätverkssäkerhet

**VPC och Subnets:**
```hcl
# infra/terraform/vpc.tf
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name = "eks-mongo-todo-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["eu-west-1a", "eu-west-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  
  enable_nat_gateway = false  # Cost optimization
  
  # EKS subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/todo-eks" = "shared"
  }
}
```

![Publika subnät taggade för EKS Load Balancers](images/subnets.jpg)
*AWS VPC Console visar public subnets med nödvändiga Kubernetes-taggar.*

**Security Groups:**

1. **Cluster Security Group** (skapad av EKS)
   - Tillåter kommunikation mellan control plane och worker nodes
   - Port 443 för API Server

2. **Node Security Group**
   ```bash
   # Tillåt all trafik mellan nodes (för pod-to-pod communication)
   aws ec2 authorize-security-group-ingress \
     --group-id sg-088f8e66e28c67fb2 \
     --protocol all \
     --source-group sg-088f8e66e28c67fb2
   ```

![Security group-regler för EKS worker nodes](images/Securtity-groups.jpg)
*VPC Console visar node security group med inbound-regler för pod-till-pod-trafik.*

**Network Policies (ej implementerat):**
För production skulle vi lägga till NetworkPolicies:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: eks-mongo-todo
spec:
  podSelector:
    matchLabels:
      app: todo-backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: mongodb
    ports:
    - protocol: TCP
      port: 27017
```

---

#### 4.4.2 IAM och RBAC

**EBS CSI Driver IAM Role (IRSA):**
```hcl
# infra/terraform/addons-ingress.tf
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
  name               = "todo-eks-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

**Förklaring:**
- IRSA (IAM Roles for Service Accounts) - Kubernetes ServiceAccount kan assume IAM role
- EBS CSI Driver behöver permissions för CreateVolume, AttachVolume, etc.
- Ingen access keys i pods - säkrare än node IAM role

![IAM-roll för EBS CSI Driver med trust policy](images/IAM-roles.jpg)
*AWS IAM Console visar rollen som används av EBS CSI Driver via IRSA.*

**Kubernetes RBAC (ej implementerat):**
För production skulle vi skapa ServiceAccounts med begränsade permissions:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: eks-mongo-todo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backend-role
  namespace: eks-mongo-todo
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backend-rolebinding
  namespace: eks-mongo-todo
subjects:
- kind: ServiceAccount
  name: backend-sa
roleRef:
  kind: Role
  name: backend-role
  apiGroup: rbac.authorization.k8s.io
```

---

#### 4.4.3 Secrets Management

**Nuvarande implementation (ej production-ready):**
```yaml
env:
- name: MONGO_URI
  value: "mongodb://root:changeme@mongodb:27017/?authSource=admin"
```

**Bättre approach - Kubernetes Secrets:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongo-credentials
  namespace: eks-mongo-todo
type: Opaque
stringData:
  username: root
  password: changeme
  uri: mongodb://root:changeme@mongodb:27017/?authSource=admin
---
# I Deployment:
env:
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      name: mongo-credentials
      key: uri
```

**Best practice - AWS Secrets Manager:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/backend-secrets-role
---
# I Deployment:
env:
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      name: mongo-credentials  # Synced från AWS Secrets Manager
      key: uri
```

Med External Secrets Operator eller AWS Secrets CSI Driver.

---

#### 4.4.4 Container Security

**Dockerfile Best Practices:**

**Backend Dockerfile:**
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY *.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .

# Security: Run as non-root
USER app
EXPOSE 8080
ENTRYPOINT ["dotnet", "todo-backend.dll"]
```

**Frontend Dockerfile:**
```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE_URL=/api
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Security: Run as non-root
USER nginx
EXPOSE 80
```

**Security features:**
- Multi-stage builds - mindre image size
- Alpine base images - färre vulnerabilities
- Non-root user - begränsar attack surface
- No secrets in images - environment variables istället

**Image Scanning (ej implementerat):**
För production: Trivy eller AWS ECR image scanning
```bash
trivy image ghcr.io/andreasvilhelmsson/todo-backend-v2:latest
```

---

#### 4.4.5 Data Encryption

**At Rest:**
- EBS volumes encrypted via StorageClass: `encrypted: "true"`
- Managed by AWS KMS

**In Transit:**
- HTTPS via Ingress (skulle kräva TLS certificate)
- MongoDB connection utan TLS (skulle behöva konfigureras)

**Production improvements:**
```yaml
# Ingress med TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: todo-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - todo.example.com
    secretName: todo-tls
  rules:
  - host: todo.example.com
    http:
      paths: [...]
```



## Egen applikation på EKS

### 4.6 Deployment Process

#### 4.6.1 CI/CD Pipeline med GitHub Actions

**Workflow för Backend:**
```yaml
# .github/workflows/backend-image.yml
name: build-backend

on:
  push:
    paths:
      - app/todo-backend/**
      - .github/workflows/backend-image.yml

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: 9.0.x }

      - name: dotnet restore
        working-directory: app/todo-backend
        run: dotnet restore

      - name: dotnet build
        working-directory: app/todo-backend
        run: dotnet build --configuration Release --no-restore

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/andreasvilhelmsson/todo-backend-v2
          tags: |
            type=raw,value=0.1.${{ github.run_number }}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: ./app/todo-backend
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha,scope=todo-backend
          cache-to: type=gha,mode=max,scope=todo-backend
```

**Workflow för Frontend:**
```yaml
# .github/workflows/frontend-image.yml
name: build-frontend

on:
  push:
    paths:
      - app/todo-frontend/**
      - .github/workflows/frontend-image.yml

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: app/todo-frontend/package-lock.json

      - name: npm ci
        working-directory: app/todo-frontend
        run: npm ci

      - name: npm build
        working-directory: app/todo-frontend
        env:
          VITE_API_BASE_URL: /api
        run: npm run build

      - uses: docker/build-push-action@v6
        with:
          context: ./app/todo-frontend
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ghcr.io/andreasvilhelmsson/todo-frontend-v2:latest
          build-args: VITE_API_BASE_URL=/api
```

**Fördelar med denna pipeline:**
- Automatisk build vid code push
- Multi-arch images (amd64 + arm64)
- Layer caching för snabbare builds
- Semantic versioning: `0.1.<run_number>`
- Preflight testing (dotnet build, npm build) innan Docker build

---

#### 4.6.2 Infrastructure as Code med Terraform

**Terraform Struktur:**
```
infra/terraform/
├── versions.tf           # Provider versions och backend
├── providers.tf          # AWS provider config
├── providers-k8s.tf      # Kubernetes/Helm providers
├── variables.tf          # Input variables
├── outputs.tf            # Output values
├── vpc.tf               # VPC module
├── eks.tf               # EKS cluster module
├── addons-ingress.tf    # EBS CSI + Ingress
└── apply-k8s.tf         # Kubernetes manifests
```

**Deployment Steps:**

**Steg 1: Skapa infrastruktur**
```bash
cd infra/terraform

# Initiera Terraform
terraform init

# Validera konfiguration
terraform validate

# Planera ändringar
terraform plan

# Applicera
terraform apply
```

**Output:**
```
Apply complete! Resources: 51 added, 0 changed, 0 destroyed.

Outputs:
cluster_endpoint = "https://xxx.gr7.eu-west-1.eks.amazonaws.com"
cluster_name = "todo-eks"
vpc_id = "vpc-0cb677ba4aa5252a0"
public_subnets = ["subnet-03ecdfca3144bf3df", "subnet-013ee60c8f7d0f689"]
```

**Steg 2: Konfigurera kubectl**
```bash
aws eks update-kubeconfig --region eu-west-1 --name todo-eks

# Verifiera
kubectl get nodes
kubectl get pods --all-namespaces
```

**Steg 3: Installera Ingress Controller**
```bash
# Lägg till Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installera
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --wait=false

# Vänta på Load Balancer
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

**Steg 4: Deploya applikation**
```bash
# Applicera alla manifests
kubectl apply -f k8s/

# Eller via Terraform (redan gjort i steg 1)
# Terraform skapar kubernetes_manifest resurser automatiskt
```

**Steg 5: Verifiera deployment**
```bash
# Kolla pods
kubectl get pods -n eks-mongo-todo

# Kolla services
kubectl get svc -n eks-mongo-todo

# Kolla ingress
kubectl get ingress -n eks-mongo-todo

# Hämta Load Balancer URL
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

![Detaljerad vy av ingress-NLB med lyssnare och målgrupper](images/load-balancer-detail.jpg)
*AWS Load Balancer Console visar listeners och target groups för ingresskontrollern.*

#### 4.6.3 Uppdatera Applikation

**Scenario: Ny feature i frontend**

**Steg 1: Utveckla och testa lokalt**
```bash
cd app/todo-frontend
npm run dev

# Testa ändringar
# Commit när klar
```

**Steg 2: Push till GitHub**
```bash
git add app/todo-frontend/
git commit -m "feat: Add new todo feature"
git push origin main
```

**Steg 3: GitHub Actions bygger automatiskt**
- Workflow triggas av push
- Bygger ny image: `ghcr.io/andreasvilhelmsson/todo-frontend-v2:0.1.42`
- Pushar till GitHub Container Registry

**Steg 4: Uppdatera Kubernetes**

**Alternativ A: Rolling restart (använder :latest tag)**
```bash
kubectl rollout restart deployment/todo-frontend -n eks-mongo-todo

# Följ status
kubectl rollout status deployment/todo-frontend -n eks-mongo-todo

# Verifiera
kubectl get pods -n eks-mongo-todo
```

**Alternativ B: Uppdatera image tag (bättre för production)**
```bash
kubectl set image deployment/todo-frontend \
  web=ghcr.io/andreasvilhelmsson/todo-frontend-v2:0.1.42 \
  -n eks-mongo-todo

# Eller via Terraform
terraform apply -var="frontend_image=ghcr.io/andreasvilhelmsson/todo-frontend-v2:0.1.42"
```

**Rollback vid problem:**
```bash
# Visa rollout history
kubectl rollout history deployment/todo-frontend -n eks-mongo-todo

# Rollback till föregående version
kubectl rollout undo deployment/todo-frontend -n eks-mongo-todo

# Rollback till specifik revision
kubectl rollout undo deployment/todo-frontend --to-revision=2 -n eks-mongo-todo
```

---

#### 4.6.4 Monitoring och Logging

**Pod Logs:**
```bash
# Visa logs
kubectl logs deployment/todo-backend -n eks-mongo-todo --tail=100

# Follow logs
kubectl logs -f deployment/todo-backend -n eks-mongo-todo

# Logs från alla pods med label
kubectl logs -l app=todo-backend -n eks-mongo-todo --all-containers=true
```

**Events:**
```bash
# Visa events i namespace
kubectl get events -n eks-mongo-todo --sort-by='.lastTimestamp'

# Watch events
kubectl get events -n eks-mongo-todo --watch
```

**Resource Usage:**
```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n eks-mongo-todo
```

**Production Monitoring (ej implementerat):**
För production skulle vi installera:
- Prometheus + Grafana för metrics
- ELK Stack eller CloudWatch för logs
- Jaeger för distributed tracing

---

### 4.7 Kostnadsanalys

**Månadskostnad:**

| Resurs | Specifikation | Kostnad/månad |
|--------|--------------|---------------|
| EKS Control Plane | Managed Kubernetes | $73 |
| EC2 Instances | 2x t3.small spot | ~$10 |
| EBS Volumes | 5GB gp3 | $0.40 |
| Network Load Balancer | 1x NLB | ~$16 |
| Data Transfer | Minimal (dev) | ~$1 |
| **Total** | | **~$100** |

**Kostnadsoptimering:**
- Spot instances istället för On-Demand (70% billigare)
- Ingen NAT Gateway (sparar $32/månad)
- Single NLB för alla services via Ingress
- gp3 istället för gp2 (20% billigare)
- Minimal node count (2 för HA)

**Skalning för production:**
- 3+ nodes för HA: +$15/månad
- NAT Gateway för private subnets: +$32/månad
- Större instances (t3.medium): +$20/månad
- Backup och monitoring: +$10/månad
- **Production total: ~$180/månad**

---

## 5. Utmaningar och Lösningar

### 5.1 Node Capacity Problem

**Problem:**
Pods fastnade i Pending state med error "Too many pods".

**Orsak:**
Single t3.small node kunde inte rymma alla system pods + application pods under rolling update.

**Lösning:**
Ökade från 1 till 2 nodes. Krävde multi-step AWS CLI commands pga EKS constraints.

**Lärdomar:**
- Planera för rolling update overhead (2x pods under update)
- t3.small kan rymma ~10-15 pods beroende på resource requests
- Använd minst 2 nodes för production

---

### 5.2 Inter-Node Networking

**Problem:**
504 Gateway Timeout när Ingress Controller (node 1) försökte nå frontend pod (node 2).

**Orsak:**
Node security group tillät inte all trafik mellan nodes. EKS skapar bara rules för specifika ports (kubelet, coredns).

**Lösning:**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-088f8e66e28c67fb2 \
  --protocol all \
  --source-group sg-088f8e66e28c67fb2
```

**Lärdomar:**
- Multi-node kluster kräver explicit security group konfiguration
- Testa pod-to-pod communication mellan nodes
- Dokumentera security group rules

---

### 5.3 Ingress Path Rewriting

**Problem:**
API calls returnerade 404 Not Found.

**Orsak:**
Ingress rewrite rule strippade `/api` prefix:
```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$1
path: /api(/|$)(.*)
```
Detta skrev om `/api/todos` → `/todos`, men backend förväntade `/api/todos`.

**Lösning:**
Tog bort rewrite och använde enkel prefix matching:
```yaml
path: /api
pathType: Prefix
```

**Lärdomar:**
- Undvik komplexa regex rewrites om möjligt
- Testa Ingress routing noggrant
- Använd `kubectl logs` på Ingress Controller för debugging

---

### 5.4 EBS CSI Driver Timeout

**Problem:**
EBS CSI addon fastnade i DEGRADED state i 20+ minuter.

**Orsak:**
Saknade IAM role med permissions för EBS operations.

**Lösning:**
Skapade IAM role med IRSA (IAM Roles for Service Accounts):
```hcl
resource "aws_iam_role" "ebs_csi" {
  name = "todo-eks-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_eks_addon" "ebs_csi" {
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  ...
}
```

**Lärdomar:**
- EKS addons behöver ofta IAM roles
- Använd IRSA istället för node IAM roles
- Kolla addon status: `kubectl get pods -n kube-system`

---

## 6. Slutsats

Detta projekt demonstrerar en komplett deployment av en modern fullstack-applikation till AWS EKS. Genom att använda Infrastructure as Code (Terraform), containerisering (Docker), och Kubernetes orchestrering har vi skapat en skalbar och maintainable lösning.

**Viktiga lärdomar:**
1. **Kubernetes är kraftfullt men komplext** - Kräver förståelse för många koncept (Pods, Services, Ingress, etc.)
2. **Infrastructure as Code är essentiellt** - Terraform gör infrastrukturen reproducerbar och versionshanterad
3. **Security är multi-layered** - Nätverk, IAM, RBAC, Secrets, Container security
4. **Monitoring är kritiskt** - Logs och metrics behövs för troubleshooting
5. **Cost optimization matters** - Spot instances, rätt sizing, minimal resurser

**Förbättringar för production:**
- [ ] Implementera NetworkPolicies
- [ ] Använd AWS Secrets Manager för credentials
- [ ] Lägg till TLS/HTTPS via cert-manager
- [ ] Installera Prometheus + Grafana
- [ ] Konfigurera HorizontalPodAutoscaler
- [ ] Implementera proper RBAC
- [ ] Lägg till health checks och readiness probes
- [ ] Konfigurera resource requests/limits
- [ ] Sätt upp backup för MongoDB
- [ ] Implementera GitOps med ArgoCD

**Resultat:**
✅ Fungerande todo-applikation på AWS EKS  
✅ Automatisk CI/CD med GitHub Actions  
✅ Infrastructure as Code med Terraform  
✅ Persistent storage med EBS  
✅ Public access via Ingress och NLB  
✅ Kostnadsoptimerad (~$100/månad)  

---

## 7. Referenser

**Dokumentation:**
- Kubernetes Official Docs: https://kubernetes.io/docs/
- AWS EKS User Guide: https://docs.aws.amazon.com/eks/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/
- NGINX Ingress Controller: https://kubernetes.github.io/ingress-nginx/

**Terraform Modules:**
- EKS Module: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/
- VPC Module: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/

**Tools:**
- kubectl: https://kubernetes.io/docs/tasks/tools/
- Helm: https://helm.sh/
- Docker: https://docs.docker.com/

**Git Repository:**
https://github.com/andreasvilhelmsson/eks-mongo-todo

---

## Appendix A: Cloudcraft Diagram Guide

**För att skapa arkitektur-diagrammet i Cloudcraft:**

1. **VPC Setup:**
   - Dra in "VPC" component
   - Sätt CIDR: 10.0.0.0/16
   - Lägg till 2 "Subnet" (public) i olika AZs
   - Lägg till "Internet Gateway"

2. **EKS Nodes:**
   - Dra in 2x "EC2" instances
   - Sätt typ: t3.small
   - Placera i olika subnets
   - Lägg till label: "EKS Worker Node"

3. **Load Balancer:**
   - Dra in "Network Load Balancer"
   - Anslut till Internet Gateway
   - Anslut till båda EC2 instances

4. **Storage:**
   - Dra in "EBS Volume"
   - Sätt storlek: 5GB, typ: gp3
   - Anslut till en EC2 instance

5. **Pods (visualisera med ikoner):**
   - Använd "DynamoDB" ikon för MongoDB (närmaste match)
   - Använd "Lambda" ikon för Backend
   - Använd "S3" ikon för Frontend
   - Placera på EC2 instances

6. **Pilar och labels:**
   - Dra pilar för trafikflöde
   - Lägg till text labels för varje komponent
   - Använd färger för att gruppera (blå för nätverk, grön för compute, orange för storage)

**Exportera:**
- File → Export → PNG (high resolution)
- Använd i rapporten

---

## Appendix B: AWS Console Screenshots Guide

**Skärmdumpar att inkludera:**

1. **EKS Console - Cluster Overview**
   - AWS Console → EKS → Clusters → todo-eks
   - Visa: Status, Version, Endpoint, API server endpoint

2. **EKS Console - Compute Tab**
   - Visa: Node group med 2 nodes, instance type, capacity type (spot)

3. **EKS Console - Add-ons Tab**
   - Visa: aws-ebs-csi-driver addon med status Active

4. **EC2 Console - Instances**
   - Visa: 2 t3.small instances med EKS tags

5. **EC2 Console - Load Balancers**
   - Visa: Network Load Balancer skapad av Ingress Controller

6. **EC2 Console - Security Groups**
   - Visa: Node security group med inbound rules

7. **EBS Console - Volumes**
   - Visa: 5GB gp3 volume kopplat till MongoDB

8. **IAM Console - Roles**
   - Visa: EBS CSI IAM role med trust policy

9. **VPC Console - Your VPCs**
   - Visa: VPC med CIDR 10.0.0.0/16

10. **Cost Explorer**
    - Visa: Kostnad per service (EKS, EC2, EBS, ELB)

**För varje screenshot:**
- Ta i ljust läge (bättre för PDF)
- Inkludera relevant information
- Beskär bort känslig data (account ID kan vara OK)
- Spara som PNG med hög kvalitet



### Design & arkitektur

- VPC med **private subnets** för noder och **public subnets** för ev. internet-facing LB.
- EKS-managed node group (billig profil: t3.small, 1–2 noder, gärna **SPOT**).
- Namespace `eks-mongo-todo` för isolering och taggning.
- Backend och frontend körs som **Deployments**; MongoDB som **StatefulSet** med **PVC**.
- Service-typ: internt **ClusterIP** mellan FE/BE; valfri extern LB/Ingress om public exponering krävs.


### IaC: Terraform för VPC + EKS

- **VPC-modul (~> 5.x)**: skapar VPC, subnät, routning, NAT (kan av för lägre kostnad).
- **Subnet-tags** för EKS & Load Balancers (t.ex. `kubernetes.io/role/internal-elb`).
- **EKS-modul (~> 19.x)**: skapar kluster, CoreDNS/kube-proxy/VPC CNI-addons och managed node group.
- **Variabler** styr region, node-typ, min/max, tags och namespace.
- All kod är **återupprepningsbar** – riv och bygg om med samma resultat.


### Containrar & CI/CD (GitHub Actions till GHCR)

- **Dockerfile backend (.NET 9)**: multi-stage (build + runtime), exponerar 8080, `ASPNETCORE_URLS=http://+:8080/`.
- **Dockerfile frontend (Node 20 + NGINX)**: bygger static assets och serverar via NGINX.
- **GitHub Actions**:
  - bygger **multi-arch** images (`linux/amd64,linux/arm64`) med Buildx/QEMU,
  - taggar `0.1.<run_number>` + `latest`,
  - push till **GHCR** (paket gärna **Public** för enkel pull från EKS).


### Kubernetes-manifest/Helm

- **Namespace** `eks-mongo-todo`.
- **MongoDB**: StatefulSet + Service + PVC (EBS via StorageClass).
- **Backend**: Deployment + Service (ClusterIP). Image från GHCR.
- **Frontend**: Deployment + Service (ClusterIP). Miljövariabel `VITE_API_BASE_URL=/api` (eller intern DNS).
- **(Valfritt)** Ingress för extern åtkomst; annars port-forward eller ALB/NLB.


### Säkerhet

- **RBAC/IRSA** för åtkomst till AWS-resurser (vid behov).
- **Secrets** för t.ex. GHCR-pull (om images privata) eller DB-lösenord.
- **NetworkPolicy** (valfritt) för att låsa trafiken mellan komponenter.
- **Namespace-isolering** och konsekventa **tags** för spårbarhet/kostnad.


### Driftsättning & test

1. `terraform init && terraform apply` → skapar VPC + EKS.
2. `aws eks update-kubeconfig --name todo-eks --region eu-west-1` → sätter kubecontext.
3. `kubectl apply -f k8s/` → lägger namespace, MongoDB, backend, frontend.
4. Verifiera:
   - `kubectl -n eks-mongo-todo get pods,svc`
   - `kubectl -n eks-mongo-todo port-forward svc/todo-backend 8090:8080` → `curl http://localhost:8090/api/health`
   - `kubectl -n eks-mongo-todo port-forward svc/todo-frontend 3000:80` → http://localhost:3000


## Arkitekturdiagram (Mermaid)

```mermaid
flowchart LR
  subgraph AWS_VPC["AWS VPC (eu-west-1)"]
    subgraph Public_Subnets["Public subnets"]
      alb[ALB/NLB (optional)]
    end
    subgraph Private_Subnets["Private subnets"]
      eks[(EKS Cluster)]
      subgraph NamespaceEks["Namespace: eks-mongo-todo"]
        fe[Frontend Deployment]
        be[Backend Deployment]
        db[(MongoDB StatefulSet + PVC/EBS)]
      end
      eks --> fe
      eks --> be
      eks --> db
    end
  end

  User((User)) -->|HTTP| alb
  alb --> fe
  fe -->|/api| be
  be --> db

  gh[GitHub Actions] --> ghcr[(GitHub Container Registry)]
  ghcr --> eks
```

## Lärdomar och fallgropar

- **ARM64 vs AMD64**: Bygg images som multi-arch (eller matcha nodernas arkitektur). Detta löste `exec format error`.
- **GHCR behörigheter**: Sätt paket till **Public** eller använd korrekt token/secret för privata paket.
- **Terraform versionsmatris**: Säkerställ kompatibilitet mellan VPC/EKS-moduler och `hashicorp/aws` provider (t.ex. VPC `~>5.x` kräver aws `~>5.x`).
- **CoreDNS DEGRADED**: Ge addons tid, öka timeouts, och kontrollera noder/iam/cni om det fastnar.
- **Kostnad**: Kör 1 nod (t3.small), SPOT, och stäng av publika ingångar när de inte behövs.


## Referenser
- Kubernetes Docs – https://kubernetes.io/docs/
- AWS EKS – https://docs.aws.amazon.com/eks/
- Terraform AWS Modules – https://github.com/terraform-aws-modules
- GitHub Actions Docker – https://github.com/docker/build-push-action
