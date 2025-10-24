#!/usr/bin/env bash
#
# =======================================================
# 🧱 rebuild.sh — Bygger, pushar och uppdaterar backend (todo-backend-v2)
# =======================================================
#  - Validerar Docker/Buildx och (valfritt) kubectl
#  - Sätter upp/återanvänder builder "multi" (docker-container)
#  - Loggar in mot GHCR om GHCR_PAT finns
#  - Bygger linux/amd64 och pushar till GHCR
#  - Uppdaterar Kubernetes-deploy om kubeconfig finns
#
#  Användning:
#    ./scripts/rebuild.sh                # taggar 0.1.<timestamp>
#    ./scripts/rebuild.sh 0.1.7          # explicit tag
#
#  Valfria miljövariabler:
#    GHCR_PAT=<token>                    # krävs om GHCR-repot är privat
#    BUILD_PROVENANCE=false              # sätt till "false" för att stänga av provenance
# =======================================================

set -euo pipefail

# ---------- Paths & konfig ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app/todo-backend"
KCFG="$ROOT/kubeconfig.yaml"
NS="eks-mongo-todo"
CACHE_DIR="$ROOT/.buildx-cache"

REG="ghcr.io/andreasvilhelmsson"
IMAGE="$REG/todo-backend-v2"
VER="${1:-0.1.$(date +%y%m%d%H%M)}"

# provenance: default true (buildx standard). Sätt BUILD_PROVENANCE=false för att stänga av.
PROVENANCE_FLAG=()
if [[ "${BUILD_PROVENANCE:-true}" == "false" ]]; then
  PROVENANCE_FLAG+=(--provenance=false)
fi

# ---------- Färgade loggar ----------
log()    { echo -e "\033[1;36m[INFO]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ---------- Preflight ----------
log "🔍 Kör preflight checks..."

command -v docker >/dev/null || { error "Docker saknas i PATH."; exit 1; }
docker info >/dev/null 2>&1 || { error "Docker daemon kör inte. Starta Docker Desktop och försök igen."; exit 1; }

if [[ ! -f "$APP/Dockerfile" ]]; then
  error "Dockerfile saknas i: $APP"
  exit 1
fi
log "✅ Dockerfile hittad: $APP/Dockerfile"

# ---------- Buildx: säkerställ builder 'multi' ----------
log "🧰 Säkerställer Buildx-builder 'multi' (docker-container)..."
if docker buildx inspect multi >/dev/null 2>&1; then
  # finns redan — använd den
  docker buildx use multi >/dev/null 2>&1 || true
  # om inaktiv, starta om den
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
  warn "⚠️  GHCR_PAT saknas. Om ditt paket är privat kommer push misslyckas."
fi

# ---------- Build & push ----------
log "🏗  Bygger image (linux/amd64) och pushar: $IMAGE:$VER"
mkdir -p "$CACHE_DIR"
set -x
docker buildx build \
  --platform linux/amd64 \
  --cache-from "type=local,src=$CACHE_DIR" \
  --cache-to "type=local,dest=$CACHE_DIR,mode=max" \
  -t "$IMAGE:$VER" \
  "${PROVENANCE_FLAG[@]}" \
  --push \
  "$APP"
set +x
log "✅ Push klar: $IMAGE:$VER"

# (Valfritt) visa manifest-info om buildx finns
if command -v docker >/dev/null 2>&1; then
  log "ℹ️  Manifestinfo (första 40 rader):"
  docker buildx imagetools inspect "$IMAGE:$VER" | sed -n '1,40p' || true
fi

# ---------- Kubernetes: uppdatera deployment om kubeconfig & kubectl finns ----------
if [[ -f "$KCFG" ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    log "🚀 Uppdaterar deployment i Kubernetes…"
    set +e
    kubectl --kubeconfig "$KCFG" -n "$NS" set image deploy/todo-backend api="$IMAGE:$VER" --record
    kubectl --kubeconfig "$KCFG" -n "$NS" rollout status deploy/todo-backend
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
echo " Image:     $IMAGE:$VER"
echo " Namespace: $NS"
echo " Plattform: linux/amd64"
echo " Provenance: ${BUILD_PROVENANCE:-true}"
echo "---------------------------------------"
