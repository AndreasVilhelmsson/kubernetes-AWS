# MongoDB Database Inspection Guide

## Metod 1: kubectl exec (Kommandorad)

### Anslut till MongoDB
```bash
# Exec into MongoDB pod
kubectl exec -it mongodb-0 -n eks-mongo-todo -- mongosh -u root -p changeme --authenticationDatabase admin
```

### Visa databaser
```javascript
show dbs
```

### Använd tododb
```javascript
use tododb
```

### Visa collections
```javascript
show collections
```

### Visa alla todos
```javascript
db.todos.find().pretty()
```

### Räkna antal todos
```javascript
db.todos.countDocuments()
```

### Visa specifik todo
```javascript
db.todos.findOne()
```

### Avsluta
```javascript
exit
```

---

## Metod 2: MongoDB Compass (GUI)

### Installera MongoDB Compass
```bash
# macOS
brew install --cask mongodb-compass

# Eller ladda ner från:
# https://www.mongodb.com/try/download/compass
```

### Port Forward MongoDB
```bash
# I en terminal, kör:
kubectl port-forward -n eks-mongo-todo mongodb-0 27017:27017
```

### Anslut med Compass
1. Öppna MongoDB Compass
2. Använd connection string:
   ```
   mongodb://root:changeme@localhost:27017/?authSource=admin
   ```
3. Klicka "Connect"
4. Navigera till: `tododb` → `todos` collection
5. Se alla dokument visuellt

**Fördelar med Compass:**
- Visuell representation av data
- Kan filtrera, sortera, editera
- Se index och schema
- Export till JSON/CSV

---

## Metod 3: Mongo Express (Web UI i Kubernetes)

### Deploy Mongo Express
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongo-express
  namespace: eks-mongo-todo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongo-express
  template:
    metadata:
      labels:
        app: mongo-express
    spec:
      containers:
      - name: mongo-express
        image: mongo-express:latest
        ports:
        - containerPort: 8081
        env:
        - name: ME_CONFIG_MONGODB_ADMINUSERNAME
          value: root
        - name: ME_CONFIG_MONGODB_ADMINPASSWORD
          value: changeme
        - name: ME_CONFIG_MONGODB_URL
          value: mongodb://root:changeme@mongodb:27017/
        - name: ME_CONFIG_BASICAUTH_USERNAME
          value: admin
        - name: ME_CONFIG_BASICAUTH_PASSWORD
          value: pass
---
apiVersion: v1
kind: Service
metadata:
  name: mongo-express
  namespace: eks-mongo-todo
spec:
  selector:
    app: mongo-express
  ports:
  - port: 8081
    targetPort: 8081
EOF
```

### Öppna Mongo Express
```bash
# Port forward
kubectl port-forward -n eks-mongo-todo svc/mongo-express 8081:8081

# Öppna i browser
open http://localhost:8081

# Login:
# Username: admin
# Password: pass
```

### Ta bort Mongo Express
```bash
kubectl delete deployment mongo-express -n eks-mongo-todo
kubectl delete service mongo-express -n eks-mongo-todo
```

---

## Exempel: Inspektera Todo Data

### Sample Output från mongosh
```javascript
tododb> db.todos.find().pretty()
[
  {
    _id: ObjectId('67a1b2c3d4e5f6789abcdef0'),
    title: 'Köp mjölk',
    completed: false,
    createdAt: ISODate('2025-01-26T10:30:00.000Z')
  },
  {
    _id: ObjectId('67a1b2c3d4e5f6789abcdef1'),
    title: 'Läs Kubernetes-bok',
    completed: true,
    createdAt: ISODate('2025-01-26T11:15:00.000Z')
  },
  {
    _id: ObjectId('67a1b2c3d4e5f6789abcdef2'),
    title: 'Deploy till EKS',
    completed: true,
    createdAt: ISODate('2025-01-26T14:20:00.000Z')
  }
]
```

### Användbara Queries

**Visa endast completed todos:**
```javascript
db.todos.find({ completed: true })
```

**Visa endast active todos:**
```javascript
db.todos.find({ completed: false })
```

**Räkna completed vs active:**
```javascript
db.todos.aggregate([
  {
    $group: {
      _id: "$completed",
      count: { $sum: 1 }
    }
  }
])
```

**Sortera efter datum:**
```javascript
db.todos.find().sort({ createdAt: -1 })
```

**Visa senaste 5 todos:**
```javascript
db.todos.find().sort({ createdAt: -1 }).limit(5)
```

---

## Backup och Export

### Export till JSON
```bash
# Port forward först
kubectl port-forward -n eks-mongo-todo mongodb-0 27017:27017 &

# Export med mongoexport
mongoexport --uri="mongodb://root:changeme@localhost:27017/tododb?authSource=admin" \
  --collection=todos \
  --out=todos-backup.json

# Stoppa port forward
kill %1
```

### Import från JSON
```bash
# Port forward
kubectl port-forward -n eks-mongo-todo mongodb-0 27017:27017 &

# Import
mongoimport --uri="mongodb://root:changeme@localhost:27017/tododb?authSource=admin" \
  --collection=todos \
  --file=todos-backup.json

# Stoppa port forward
kill %1
```

---

## Screenshot för Rapport

För att ta screenshot av MongoDB data:

1. **Använd MongoDB Compass:**
   - Port forward: `kubectl port-forward -n eks-mongo-todo mongodb-0 27017:27017`
   - Anslut med Compass
   - Navigera till `tododb.todos`
   - Ta screenshot av Documents view

2. **Eller använd mongosh:**
   ```bash
   kubectl exec -it mongodb-0 -n eks-mongo-todo -- mongosh -u root -p changeme --authenticationDatabase admin
   use tododb
   db.todos.find().pretty()
   ```
   - Ta screenshot av terminal output

3. **Eller använd Mongo Express:**
   - Deploy Mongo Express (se ovan)
   - Port forward och öppna i browser
   - Ta screenshot av web UI

---

## Troubleshooting

### Connection refused
```bash
# Kolla att MongoDB pod körs
kubectl get pods -n eks-mongo-todo

# Kolla logs
kubectl logs mongodb-0 -n eks-mongo-todo
```

### Authentication failed
```bash
# Verifiera credentials i StatefulSet
kubectl get statefulset mongodb -n eks-mongo-todo -o yaml | grep -A 5 env
```

### Port forward timeout
```bash
# Kör port forward i bakgrunden
kubectl port-forward -n eks-mongo-todo mongodb-0 27017:27017 > /dev/null 2>&1 &

# Spara PID för att kunna stoppa senare
echo $! > /tmp/mongo-pf.pid

# Stoppa senare
kill $(cat /tmp/mongo-pf.pid)
```
