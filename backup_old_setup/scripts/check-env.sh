#!/usr/bin/env bash
set -euo pipefail

fail(){ echo "❌ $1"; exit 1; }
ok(){ echo "✅ $1"; }

echo "🔍 Preflight checks…"

# 1) AWS CLI
aws sts get-caller-identity >/dev/null 2>&1 || fail "AWS CLI ej inloggad. Kör: aws configure"
ok "AWS: inloggad"

# 2) Terraform
terraform version >/dev/null 2>&1 || fail "Terraform saknas i PATH"
ok "Terraform: hittad"

# 3) Docker
docker info >/dev/null 2>&1 || fail "Docker daemon kör inte (starta Docker Desktop)"
ok "Docker: kör"

# 4) GHCR token (valfritt om imagen är public)
if [[ -z "${GHCR_PAT:-}" ]]; then
  echo "⚠️  GHCR_PAT ej satt (behövs om imagen är privat)"
else
  ok "GHCR_PAT: satt"
fi

# 5) kubeconfig + klusterkontakt
[[ -f "./kubeconfig.yaml" ]] || fail "kubeconfig.yaml saknas i projektroten"
kubectl version --client --output=yaml >/dev/null 2>&1 || fail "Kubectl når inte klustret"
kubectl --kubeconfig ./kubeconfig.yaml get nodes >/dev/null 2>&1 || fail "Kunde inte lista noder"
ok "Kubernetes: kontakt OK"

# 6) Terraform-mapp
[[ -d "infra/terraform" ]] || fail "infra/terraform saknas"
ok "Projektstruktur OK"

echo "🎉 Alla preflight-checks passerade!"