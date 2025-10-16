# 🧩 Solution Report — GitHub Actions Build for Backend (offline workaround on macOS)

**Project:** `eks-mongo-todo`  
**Date:** 2025-10-15  
**Reporter:** Codex  

---

## 1️⃣ Summary
Local Docker builds of the .NET 9 backend (`app/todo-backend`) repeatedly stalled during the `dotnet restore` step on an Apple Silicon Mac. After multiple attempts (offline NuGet feeds, cache tweaks, diag logs), the practical resolution was to perform the container build in GitHub Actions (ubuntu-latest, amd64) and keep running locally only the published GHCR image. The same approach is recommended for the frontend.

---

## 2️⃣ Issue Background
- Local environment: macOS (ARM64). Docker build set to `--platform linux/amd64` for EKS compatibility.
- `dotnet restore` executed inside BuildKit containers. Network traffic to nuget.org appeared intermittently blocked/stalled; restore waited indefinitely (30+ minutes).
- Offline cache attempts (copying `.nupkg` etc.) struggled because reference packs come from `/usr/local/share/dotnet/packs` and differ across architectures.

---

## 3️⃣ Resolution

1. **Switch builds to GitHub Actions**  
   - Workflow `.github/workflows/backend-image.yml` now runs on `ubuntu-latest`, builds both `linux/amd64` and `linux/arm64` images using buildx, pushes to GHCR.
   - Multi-architecture setup via `docker/setup-qemu-action@v3`.

2. **Local testing**  
   - Pull the pushed image (`ghcr.io/andreasvilhelmsson/todo-backend-v2:<tag>`) and run via `docker run -p 8090:8080 ...` for sanity checks.

3. **Deployment**  
   - Update EKS manifests to use the GHCR image tags.

---

## 4️⃣ Suggested Next Steps (Frontend)
- Mirror the backend workflow for the frontend build: add a GitHub Actions workflow to build/push the frontend image (React) for both `linux/amd64` and `linux/arm64`.
- Test locally by pulling the built frontend image.
- Optionally, update backend+frontend workflows to include deployment steps (kubectl/helm).

---

## 5️⃣ Lessons Learned
- Building multi-architecture Docker images on Apple Silicon without reliable network access is fragile. CI/CD (GitHub Actions) provides stable network, CPU architecture, and caches.
- Offline NuGet packages must include reference packs that exist outside `~/.nuget`; replicating them manually is error-prone.
- Keeping Docker builds in CI avoids local environment variability (VPN, proxies, platform emulation).

---

## 6️⃣ Status
✅ Backend image (0.1.6) built and confirmed locally via GHCR pull.  
⚠️ Frontend still needs similar CI workflow and verification.

