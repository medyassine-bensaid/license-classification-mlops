#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# generate_all.sh
# Writes the project structure and all files for a local single-VM GitOps MLOps setup:
#  - mlops-single-vm/ (terraform, ansible)
#  - mlops-manifests/ (ArgoCD App-of-Apps with Helm child Applications)
#
# After running this script, run setup_all.sh (edited with your env vars) to deploy.

WD="$(pwd)"
echo "Generating project files under: $WD"

# Prevent overwriting existing directories without backup
if [[ -d mlops-single-vm || -d mlops-manifests ]]; then
  TIMESTAMP=$(date +%s)
  [[ -d mlops-single-vm ]] && mv mlops-single-vm mlops-single-vm.bak."$TIMESTAMP"
  [[ -d mlops-manifests ]] && mv mlops-manifests mlops-manifests.bak."$TIMESTAMP"
  echo "Existing project dirs moved to backups with suffix .$TIMESTAMP"
fi

########################
# mlops-single-vm
########################
mkdir -p mlops-single-vm/terraform
mkdir -p mlops-single-vm/ansible
mkdir -p mlops-single-vm/values

cat > mlops-single-vm/terraform/variables.tf <<'TFVARS'
variable "vm_ip"            { description = "Public IP/DNS of the VM" type = string }
variable "vm_user"          { description = "SSH username (e.g., ubuntu)" type = string }
variable "private_key_path" { description = "Path to SSH private key on local machine" type = string }
TFVARS

cat > mlops-single-vm/terraform/main.tf <<'TFMAIN'
# Terraform is used only to run local "provisioner-like" actions via a null_resource.
# For this local-VM flow the file is mostly a placeholder that the later script uses.
terraform {
  required_version = ">= 1.6.0"
}
resource "null_resource" "vm_preparer" {
  triggers = {
    vm_ip = var.vm_ip
    user  = var.vm_user
  }
}
TFMAIN

cat > mlops-single-vm/terraform/terraform.tfvars <<'TFTF'
# Customize these values for your VM before running setup_all.sh
vm_ip            = "YOUR_VM_IP"
vm_user          = "ubuntu"
private_key_path = "~/.ssh/id_rsa"
TFTF

# Ansible inventory (will be patched by setup_all.sh if you export env vars)
cat > mlops-single-vm/ansible/inventory.ini <<'INV'
[k8s]
YOUR_VM_IP ansible_user=ubuntu ansible_ssh_private_key_file=/home/YOUR_LOCAL_USER/.ssh/id_rsa
INV

# Ansible playbook: installs K3s (disable Traefik), installs ingress-nginx and ArgoCD.
cat > mlops-single-vm/ansible/site.yaml <<'PLAY'
- name: Install K3s, ingress-nginx and ArgoCD on remote Ubuntu VM
  hosts: k8s
  become: true
  gather_facts: false

  tasks:
    - name: Ensure required apt packages present
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        state: present
        update_cache: yes

    - name: Install Docker (if not present)
      shell: |
        set -euxo pipefail
        if ! command -v docker >/dev/null 2>&1; then
          sudo install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          sudo apt-get update -y
          sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        fi
      args:
        executable: /bin/bash

    - name: Install K3s (disable Traefik)
      shell: |
        set -euxo pipefail
        if [[ ! -x /usr/local/bin/k3s ]]; then
          curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode=0644" sh -
        fi
      args:
        creates: /usr/local/bin/k3s
        executable: /bin/bash

    - name: Wait for kubeconfig on remote
      wait_for:
        path: /etc/rancher/k3s/k3s.yaml
        timeout: 120

    - name: Fetch kubeconfig to controller (local machine)
      fetch:
        src: /etc/rancher/k3s/k3s.yaml
        dest: ../kubeconfig
        flat: yes

    - name: Replace 127.0.0.1 in the fetched kubeconfig with remote host (local edit)
      local_action: shell |
        sed -i "s/127.0.0.1/{{ inventory_hostname }}/g" ./kubeconfig
      run_once: true

    - name: Install Helm and add ingress-nginx repo on remote
      shell: |
        set -euxo pipefail
        if ! command -v helm >/dev/null 2>&1; then
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        fi
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
        helm repo update
      args:
        executable: /bin/bash

    - name: Install ingress-nginx via Helm (controller.service.type=NodePort)
      shell: |
        set -euxo pipefail
        kubectl create namespace ingress-nginx || true
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx \
          --set controller.service.type=NodePort --wait
      args:
        executable: /bin/bash

    - name: Install ArgoCD (official manifest)
      shell: |
        set -euxo pipefail
        kubectl create namespace argocd || true
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        kubectl -n argocd rollout status deployment argocd-server --timeout=180s || true
      args:
        executable: /bin/bash

    - name: Print ArgoCD initial admin password (for user to copy)
      shell: |
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true
      register: argocd_pass
      changed_when: false

    - name: Show admin password in ansible output
      debug:
        msg: "ArgoCD initial admin password: {{ argocd_pass.stdout }}"
PLAY

# simple values placeholders (you can customize later)
cat > mlops-single-vm/values/airflow-values.yaml <<'VAF'
executor: KubernetesExecutor
web:
  service:
    type: ClusterIP
postgresql:
  enabled: true
workers:
  replicas: 1
webserver:
  defaultUser:
    enabled: true
    username: admin
    password: admin123
VAF

cat > mlops-single-vm/values/mlflow-values.yaml <<'VMV'
postgresql:
  enabled: true
service:
  type: ClusterIP
artifactRoot: "s3://mlflow"
extraEnvVars:
  - name: MLFLOW_S3_ENDPOINT_URL
    value: "http://minio.mlflow-system.svc.cluster.local:9000"
VMV

cat > mlops-single-vm/values/minio-values.yaml <<'VMIN'
auth:
  rootUser: minio
  rootPassword: minioStrongPass123!
defaultBuckets: "mlflow"
service:
  type: ClusterIP
VMIN

cat > mlops-single-vm/values/argocd-values.yaml <<'VARG'
# Keep ArgoCD defaults for now
VARG

########################
# mlops-manifests (App-of-Apps + child Helm Applications)
########################
mkdir -p mlops-manifests/apps/staging-apps
mkdir -p mlops-manifests/apps/production-apps

# top-level app-of-apps (staging)
cat > mlops-manifests/apps/staging.yaml <<'STAGEAPP'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mlops-staging-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "REPLACE_WITH_REPO_URL"
    targetRevision: main
    path: apps/staging-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
STAGEAPP

# top-level app-of-apps (production)
cat > mlops-manifests/apps/production.yaml <<'PRODAPP'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mlops-production-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "REPLACE_WITH_REPO_URL"
    targetRevision: main
    path: apps/production-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
PRODAPP

# STAGING child Helm Apps
cat > mlops-manifests/apps/staging-apps/minio-staging.yaml <<'MINIOST'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minio-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://charts.bitnami.com/bitnami"
    chart: minio
    targetRevision: "11.0.0"
    helm:
      values: |
        auth:
          rootUser: minio
          rootPassword: minioStrongPass123!
        service:
          type: ClusterIP
        defaultBuckets: "mlflow"
  destination:
    server: https://kubernetes.default.svc
    namespace: mlflow-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MINIOST

cat > mlops-manifests/apps/staging-apps/mlflow-staging.yaml <<'MLFST'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mlflow-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://charts.bitnami.com/bitnami"
    chart: mlflow
    targetRevision: "1.3.0"
    helm:
      values: |
        postgresql:
          enabled: true
        service:
          type: ClusterIP
        artifactRoot: "s3://mlflow"
        extraEnvVars:
          - name: MLFLOW_S3_ENDPOINT_URL
            value: "http://minio.mlflow-system.svc.cluster.local:9000"
  destination:
    server: https://kubernetes.default.svc
    namespace: mlflow-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MLFST

cat > mlops-manifests/apps/staging-apps/airflow-staging.yaml <<'AIRST'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: airflow-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://airflow.apache.org/"
    chart: airflow
    targetRevision: "1.18.0"
    helm:
      values: |
        executor: "KubernetesExecutor"
        web:
          service:
            type: ClusterIP
        postgresql:
          enabled: true
        workers:
          replicas: 1
        webserver:
          defaultUser:
            enabled: true
            username: admin
            password: admin123
  destination:
    server: https://kubernetes.default.svc
    namespace: airflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
AIRST

cat > mlops-manifests/apps/staging-apps/seldon-staging.yaml <<'SELST'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: seldon-core-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://storage.googleapis.com/seldon-charts"
    chart: seldon-core-operator
    targetRevision: "1.17.1"
    helm:
      values: |
        istio:
          enabled: false
        usageMetrics:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: seldon-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
SELST

cat > mlops-manifests/apps/staging-apps/monitoring-staging.yaml <<'MONST'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://prometheus-community.github.io/helm-charts"
    chart: kube-prometheus-stack
    targetRevision: "77.0.0"
    helm:
      values: |
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
        grafana:
          adminPassword: "admin"
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MONST

# PRODUCTION child Helm Apps (copy staging but stronger defaults)
cat > mlops-manifests/apps/production-apps/minio-prod.yaml <<'MINIOPR'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minio-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://charts.bitnami.com/bitnami"
    chart: minio
    targetRevision: "11.0.0"
    helm:
      values: |
        auth:
          rootUser: minio
          rootPassword: ChangeMeProdMinioPass!
        service:
          type: ClusterIP
        defaultBuckets: "mlflow"
  destination:
    server: https://kubernetes.default.svc
    namespace: mlflow-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MINIOPR

cat > mlops-manifests/apps/production-apps/mlflow-prod.yaml <<'MLFPR'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mlflow-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://charts.bitnami.com/bitnami"
    chart: mlflow
    targetRevision: "1.3.0"
    helm:
      values: |
        postgresql:
          enabled: true
        service:
          type: ClusterIP
        replicaCount: 2
        artifactRoot: "s3://mlflow"
        extraEnvVars:
          - name: MLFLOW_S3_ENDPOINT_URL
            value: "http://minio.mlflow-system.svc.cluster.local:9000"
  destination:
    server: https://kubernetes.default.svc
    namespace: mlflow-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MLFPR

cat > mlops-manifests/apps/production-apps/airflow-prod.yaml <<'AIRPR'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: airflow-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://airflow.apache.org/"
    chart: airflow
    targetRevision: "1.18.0"
    helm:
      values: |
        executor: "KubernetesExecutor"
        web:
          service:
            type: ClusterIP
        postgresql:
          enabled: true
        workers:
          replicas: 2
        webserver:
          defaultUser:
            enabled: true
            username: admin
            password: ChangeMeProdAirflowPass!
  destination:
    server: https://kubernetes.default.svc
    namespace: airflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
AIRPR

cat > mlops-manifests/apps/production-apps/seldon-prod.yaml <<'SELPR'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: seldon-core-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://storage.googleapis.com/seldon-charts"
    chart: seldon-core-operator
    targetRevision: "1.17.1"
    helm:
      values: |
        istio:
          enabled: false
        usageMetrics:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: seldon-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
SELPR

cat > mlops-manifests/apps/production-apps/monitoring-prod.yaml <<'MONPR'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://prometheus-community.github.io/helm-charts"
    chart: kube-prometheus-stack
    targetRevision: "77.0.0"
    helm:
      values: |
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
        grafana:
          adminPassword: "ChangeMeProdGrafanaPass!"
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
MONPR

# README_HELP
cat > README_SETUP.md <<'RM'
Quickflow after generation:
1) Edit mlops-single-vm/terraform/terraform.tfvars - set vm_ip, vm_user, private_key_path
2) Edit mlops-single-vm/ansible/inventory.ini - replace YOUR_VM_IP and /home/YOUR_LOCAL_USER/.ssh/id_rsa
3) Create a remote Git repo for mlops-manifests (or use an existing one) and obtain its HTTPS URL.
4) Edit mlops-manifests/apps/staging.yaml and apps/production.yaml, replace REPLACE_WITH_REPO_URL with your repo HTTPS URL.
5) Run setup_all.sh with env vars:
   VM_IP=your_vm_ip VM_USER=ubuntu PRIVATE_KEY=~/.ssh/id_rsa GITHUB_REPO=https://github.com/you/mlops-manifests.git ./setup_all.sh
RM

echo "Generation complete. Files created:"
echo " - mlops-single-vm/"
echo " - mlops-manifests/"
echo "Read README_SETUP.md for next steps."
