#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app/todo-backend"

docker build \
  --progress=plain \
  --platform linux/amd64 \
  -t todo-backend-local:latest \
  "$APP"
