#!/usr/bin/env bash
#
# =======================================================
# 🎨 rebuild-frontend.sh — Bygger/pushar frontend + uppdaterar K8s
# =======================================================
#  - Återanvänder/bootstrapp-ar Buildx "multi" (docker-container)
#  - Loggar in mot GHCR om GHCR_PAT finns
#  - (Valfritt) skriver .env.production för Vite om VITE_API_BASE_URL är satt
#  - Bygger linux/amd64 och pushar till GHCR
#  - Uppdaterar Kubernetes-deployment (om kubeconfig finns)
#
#  Användning:
#    ./scripts/rebuild-frontend.sh              # taggar 0.1.<timestamp>
#    ./scripts/rebuild-frontend.sh 0.1.12       # explicit tag
#
#  Miljövariabler:
#    GHCR_PAT=<token med write:packages>        # krävs om GHCR-paketet är privat
#    VITE_API_BASE_URL="https://api.example"    # om satt, genereras .env.production
#    BUILD_PROVENANCE=false                     # stäng av provenance vid behov
# =======================================================

set -euo pipefail

# ---------- Paths & konfig ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app/todo-frontend"                 # <- din frontend-kod
KCFG="$ROOT/kubeconfig.yaml"
NS="eks-mongo-todo"

REG="ghcr.io/andreasvilhelmsson"
IMAGE="$REG/todo-frontend"
VER="${1:-0.1.$(date +%y%m%d%H%M)}"

# container-namnet i deploymenten (matcha k8s/frontend/deploy.yaml)
K8S_DEPLOY="todo-frontend"
K8S_CONTAINER="web"

# provenance: default true. Sätt BUILD_PROVENANCE=false för att stänga av.
PROVENANCE_FLAG=()
if [[ "${BUILD_PROVENANCE:-true}" == "false" ]]; then
  PROVENANCE_FLAG+=(--provenance=false)
fi

# ---------- Färgade loggar ----------
log()    { echo -e "\033[1;36m[INFO]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ---------- Preflight ----------
log "🔍 Kör preflight checks…"
command -v docker >/dev/null || { error "Docker saknas i PATH."; exit 1; }
docker info >/dev/null 2>&1 || { error "Docker daemon kör inte. Starta Docker Desktop."; exit 1; }

# Frontendens Dockerfile måste finnas (ex. multi-stage Node->Nginx)
if [[ ! -f "$APP/Dockerfile" ]]; then
  error "Dockerfile saknas i: $APP"
  exit 1
fi
log "✅ Dockerfile hittad: $APP/Dockerfile"

# ---------- Buildx: säkerställ builder 'multi' ----------
log "🧰 Säkerställer Buildx-builder 'multi' (docker-container)…"
if docker buildx inspect multi >/dev/null 2>&1; then
  docker buildx use multi >/dev/null 2>&1 || true
  if ! docker buildx inspect multi | grep -q "Status: running"; then
    warn "Builder 'multi' var inte running — startar om den…"
    docker buildx stop multi >/dev/null 2>&1 || true
    docker buildx rm -f multi >/dev/null 2>&1 || true
    docker buildx create --name multi --driver docker-container --use --bootstrap >/dev/null
  fi
else
  docker buildx create --name multi --driver docker-container --use --bootstrap >/dev/null
fi
docker buildx inspect multi | sed -n '1,30p' || true

# ---------- GHCR login (om token finns) ----------
if [[ -n "${GHCR_PAT:-}" ]]; then
  log "🔑 Loggar in på GHCR…"
  echo "$GHCR_PAT" | docker login ghcr.io -u andreasvilhelmsson --password-stdin >/dev/null
  log "✅ Inloggad mot ghcr.io"
else
  warn "⚠️  GHCR_PAT saknas. Om paketet är privat kommer push misslyckas."
fi

# ---------- Vite .env.production (valfritt) ----------
TMP_ENV_CREATED=false
if [[ -n "${VITE_API_BASE_URL:-}" ]]; then
  log "📝 Skapar/uppdaterar .env.production för Vite (VITE_API_BASE_URL)…"
  echo "VITE_API_BASE_URL=${VITE_API_BASE_URL}" > "$APP/.env.production"
  TMP_ENV_CREATED=true
fi

# ---------- Build & push ----------
log "🏗  Bygger frontend-image (linux/amd64) och pushar: $IMAGE:$VER"
set -x
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE:$VER" \
  "${PROVENANCE_FLAG[@]}" \
  --push \
  "$APP"
set +x
log "✅ Push klar: $IMAGE:$VER"

# städa temporär env om vi skapade den
if [[ "$TMP_ENV_CREATED" == "true" ]]; then
  rm -f "$APP/.env.production" || true
fi

# ---------- Manifestinfo (frivilligt) ----------
log "ℹ️  Manifestinfo (första 40 rader):"
docker buildx imagetools inspect "$IMAGE:$VER" | sed -n '1,40p' || true

# ---------- Kubernetes: uppdatera deployment ----------
if [[ -f "$KCFG" ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    log "🚀 Uppdaterar K8s-deployment: $K8S_DEPLOY ($K8S_CONTAINER)…"
    set +e
    kubectl --kubeconfig "$KCFG" -n "$NS" set image "deploy/$K8S_DEPLOY" "$K8S_CONTAINER=$IMAGE:$VER" --record
    kubectl --kubeconfig "$KCFG" -n "$NS" rollout status "deploy/$K8S_DEPLOY"
    set -e
  else
    warn "⚠️  kubectl saknas i PATH — hoppar över deploy-uppdatering."
  fi
else
  warn "⚠️  $KCFG saknas — hoppar över deploy-uppdatering."
fi

# ---------- Sammanfattning ----------
log "✅ Klart!"
echo "---------------------------------------"
echo " Image:       $IMAGE:$VER"
echo " Namespace:   $NS"
echo " Deployment:  $K8S_DEPLOY"
echo " Container:   $K8S_CONTAINER"
echo " Plattform:   linux/amd64"
echo " Provenance:  ${BUILD_PROVENANCE:-true}"
[[ -n "${VITE_API_BASE_URL:-}" ]] && echo " Vite API URL: $VITE_API_BASE_URL"
echo "---------------------------------------"