# 🧩 Fail Report — Docker Build Architecture Mismatch

**Project:** `EKS-MONGO-TODO`  
**Date:** 2025-10-13  
**Author:** Andreas Vilhelmsson  

---

## 1️⃣ Summary
När backend-containern `ghcr.io/andreasvilhelmsson/todo-backend:0.1.0` startades i EKS fick vi felet:

```
exec /bin/sh: exec format error
```

Detta visade sig bero på att Docker-imagen var byggd för **fel CPU-arkitektur** (`arm64`) medan EKS-noderna körde **amd64**.

---

## 2️⃣ Root Cause
- Projektet byggdes lokalt på **MacBook M1 (Apple Silicon, ARM64)**.  
- Docker använder Apple Silicon som default → bygger `linux/arm64` images.  
- EKS-noder i AWS (EC2) kör `linux/amd64`.  
- Kubernetes försökte köra `arm64`-imagen på `amd64`-noden → “exec format error”.

---

## 3️⃣ Evidence
Kommando för att verifiera nodarkitektur:
```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.nodeInfo.architecture}{"\n"}{end}'
```
Output:
```
ip-10-77-101-246.eu-west-1.compute.internal  amd64
```

Byggd image:
```bash
docker buildx imagetools inspect ghcr.io/andreasvilhelmsson/todo-backend:0.1.0
```
Visade `linux/arm64`.

---

## 4️⃣ Resolution
Byggde om imagen med explicit `--platform linux/amd64`:
```bash
docker buildx build --platform linux/amd64   -t ghcr.io/andreasvilhelmsson/todo-backend:0.1.1   --push .
```

Uppdaterade deployment:
```yaml
containers:
  - name: api
    image: ghcr.io/andreasvilhelmsson/todo-backend:0.1.1
```

Resultat:
✅ Pod startar korrekt på EKS-noden.

---

## 5️⃣ Preventive Actions (IaC Fix)
För att undvika samma fel framöver:

1. **Lägg till build-plattform i Dockerfile-kommentarer:**
   ```Dockerfile
   # NOTE: Build with --platform linux/amd64 for EKS compatibility
   ```

2. **Skapa en Build-scriptfil:** `scripts/build_backend.sh`
   ```bash
   #!/bin/bash
   docker buildx build --platform linux/amd64      -t ghcr.io/andreasvilhelmsson/todo-backend:$1      --push .
   ```

3. **Integrera i CI/CD (GitHub Actions):**
   ```yaml
   runs-on: ubuntu-latest
   steps:
     - uses: actions/checkout@v4
     - uses: docker/setup-buildx-action@v3
     - run: docker buildx build --platform linux/amd64 -t ghcr.io/... --push .
   ```

4. Dokumentera i README.md att projektet körs på **amd64**-noder i AWS.

---

## 6️⃣ Lessons Learned
- Bygg alltid images för samma arkitektur som klustrets noder.  
- Dokumentera plattform i både Dockerfile och CI/CD.  
- Testa images lokalt innan push via `docker run` på rätt plattform.  
- Använd multi-arch-builds om man vill ha portabilitet (`--platform linux/amd64,linux/arm64`).

---
