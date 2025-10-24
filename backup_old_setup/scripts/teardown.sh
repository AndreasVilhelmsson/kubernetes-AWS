#!/usr/bin/env bash
set -euo pipefail
echo "🧹 Startar teardown..."

# 1️⃣ Rensa Kubernetes namespace (om det finns)
kubectl --kubeconfig ./kubeconfig.yaml delete ns eks-mongo-todo --ignore-not-found=true || true

# 2️⃣ Gå till Terraform-mappen
cd infra/terraform

# 3️⃣ Initiera och förstör hela miljön (EKS, VPC, allt)
terraform init -upgrade
terraform destroy -auto-approve

# 4️⃣ Rensa Docker-build cache
cd ../../
rm -rf .docker-cache || true

# 5️⃣ Rensa eventuell buildx-builder (startar om på nästa build)
docker buildx ls | grep -q multi && docker buildx rm multi || true
docker buildx create --use --name multi

echo "✅ Teardown klar – allt är rensat."