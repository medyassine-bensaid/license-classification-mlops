#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# setup_all.sh
# Usage:
# VM_IP=203.0.113.12 VM_USER=ubuntu PRIVATE_KEY=~/.ssh/id_rsa GITHUB_REPO=https://github.com/you/mlops-manifests.git ./setup_all.sh

VM_IP="${VM_IP:-}"
VM_USER="${VM_USER:-ubuntu}"
PRIVATE_KEY="${PRIVATE_KEY:-$HOME/.ssh/id_rsa}"
GITHUB_REPO="${GITHUB_REPO:-}"
BRANCH="${BRANCH:-main}"
TIMEOUT_SYNC="${TIMEOUT_SYNC:-1200}" # seconds to wait for ArgoCD apps
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"

if [[ -z "$VM_IP" || -z "$GITHUB_REPO" ]]; then
  echo "Usage: VM_IP=... GITHUB_REPO=... PRIVATE_KEY=... VM_USER=... ./setup_all.sh"
  exit 1
fi

PRIVATE_KEY="$(realpath -m "$PRIVATE_KEY")"
echo "Using VM_IP=$VM_IP, VM_USER=$VM_USER, PRIVATE_KEY=$PRIVATE_KEY, GITHUB_REPO=$GITHUB_REPO"

# quick SSH check
echo "Checking SSH connectivity..."
if ! ssh -i "$PRIVATE_KEY" -o BatchMode=yes -o ConnectTimeout=10 "${VM_USER}@${VM_IP}" 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
  echo "ERROR: cannot SSH to ${VM_USER}@${VM_IP} with ${PRIVATE_KEY}. Fix SSH and retry."
  exit 2
fi
echo "SSH OK."

# Patch terraform.tfvars and inventory.ini
TFVARS="mlops-single-vm/terraform/terraform.tfvars"
if [[ -f "$TFVARS" ]]; then
  sed -i "s/YOUR_VM_IP/${VM_IP}/g" "$TFVARS" || true
  sed -i "s|~/.ssh/id_rsa|${PRIVATE_KEY}|g" "$TFVARS" || true
fi

INV="mlops-single-vm/ansible/inventory.ini"
if [[ -f "$INV" ]]; then
  sed -i "s/YOUR_VM_IP/${VM_IP}/g" "$INV" || true
  sed -i "s|/home/YOUR_LOCAL_USER/.ssh/id_rsa|${PRIVATE_KEY}|g" "$INV" || true
fi

# run terraform (here it's a placeholder; included for completeness)
if command -v terraform >/dev/null 2>&1; then
  echo "Running terraform init & apply (no cloud resources planned) ..."
  pushd mlops-single-vm/terraform >/dev/null
  terraform init -input=false >/dev/null || true
  terraform apply -auto-approve -input=false || true
  popd >/dev/null
else
  echo "Terraform not found locally — skipping terraform step (ok for local VM flow)."
fi

# run ansible playbook to install K3s, ingress-nginx and ArgoCD
echo "Running Ansible playbook to install K3s + ingress-nginx + ArgoCD on the VM..."
pushd mlops-single-vm/ansible >/dev/null
# ensure collections are installed
ansible-galaxy collection install kubernetes.core community.kubernetes community.general --force >/dev/null || true
ansible-playbook -i inventory.ini site.yaml
popd >/dev/null

# confirm kubeconfig has been fetched
KUBECONFIG_LOCAL="$(pwd)/mlops-single-vm/kubeconfig"
if [[ ! -f "$KUBECONFIG_LOCAL" ]]; then
  echo "ERROR: kubeconfig not found at $KUBECONFIG_LOCAL. Ensure ansible fetch succeeded."
  exit 3
fi
export KUBECONFIG="$KUBECONFIG_LOCAL"
echo "KUBECONFIG set to $KUBECONFIG"

echo "Cluster nodes:"
kubectl get nodes -o wide

# Prepare manifests repo: set repo URL in apps top-level if placeholder present
echo "Patching mlops-manifests/apps/* to point to $GITHUB_REPO ..."
find mlops-manifests -type f -name '*.yaml' -exec sed -i "s|REPLACE_WITH_REPO_URL|${GITHUB_REPO}|g" {} +

# If local mlops-manifests isn't a git repo yet, initialize & push
pushd mlops-manifests >/dev/null
if [[ ! -d .git ]]; then
  git init
  git checkout -b "$BRANCH" || true
  git add -A
  git commit -m "initial mlops manifests (generated)" || true
  git remote add origin "$GITHUB_REPO" || true
  echo "Attempting to push manifests to remote (may prompt for credentials)..."
  git push -u origin "$BRANCH" || echo "Push failed (authenticate and push manually from mlops-manifests/)"
else
  echo "Local mlops-manifests already a git repo; ensure remote exists and push changes."
  git add -A
  if ! git diff --staged --quiet; then
    git commit -m "update manifests" || true
  fi
  git push origin "$BRANCH" || echo "Push failed (authenticate and push manually)"
fi
popd >/dev/null

# Apply app-of-apps to ArgoCD (so ArgoCD begins to install child Helm charts)
echo "Applying top-level App-of-Apps to ArgoCD..."
kubectl apply -f mlops-manifests/apps/staging.yaml -n argocd || true
kubectl apply -f mlops-manifests/apps/production.yaml -n argocd || true

# wait for argocd-server ready
kubectl -n argocd rollout status deployment argocd-server --timeout=180s || true

# Wait for ArgoCD to register child apps and sync them
echo "Waiting for ArgoCD child Applications to appear and sync (timeout ${TIMEOUT_SYNC}s)..."
apps_expected=(minio-staging mlflow-staging airflow-staging seldon-core-staging monitoring-staging minio-prod mlflow-prod airflow-prod seldon-core-prod monitoring-prod)
elapsed=0

until kubectl -n argocd get applications.argoproj.io >/dev/null 2>&1; do sleep 2; ((elapsed+=2)); if (( elapsed > TIMEOUT_SYNC )); then break; fi; done

while (( elapsed < TIMEOUT_SYNC )); do
  all_ok=true
  for app in "${apps_expected[@]}"; do
    if ! kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
      echo "App ${app} not yet created in ArgoCD"
      all_ok=false
      continue
    fi
    sync_status=$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    health_status=$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo "App ${app}: sync=${sync_status:-Unknown}, health=${health_status:-Unknown}"
    if [[ "${sync_status}" != "Synced" || "${health_status}" != "Healthy" ]]; then
      all_ok=false
    fi
  done
  if [[ "$all_ok" == "true" ]]; then
    echo "All expected apps are Synced & Healthy."
    break
  fi
  sleep "$CHECK_INTERVAL"
  elapsed=$((elapsed + CHECK_INTERVAL))
done

if (( elapsed >= TIMEOUT_SYNC )); then
  echo "Timeout waiting for ArgoCD apps to sync. Inspect ArgoCD UI and pod events for details."
fi

# Quick smoke tests: check nip.io hostnames (staging)
echo "Quick smoke tests for staging (nip.io hostnames):"
for svc in mlflow airflow minio seldon monitoring; do
  host="${svc}.staging.${VM_IP}.nip.io"
  echo -n "Testing http://${host} ... "
  if curl -fsS -m 10 "http://${host}" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAILED (Ingress/service may not expose HTTP root page; check 'kubectl get ingress -A')"
  fi
done

echo
echo "Setup script finished. To inspect ArgoCD UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  open https://localhost:8080  (user: admin; password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
