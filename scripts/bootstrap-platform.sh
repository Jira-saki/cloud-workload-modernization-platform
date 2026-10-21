#!/usr/bin/env bash
# ==============================================================================
# Script: bootstrap-platform.sh
# Purpose: Cluster initialization and GitOps platform bootstrapping
# ==============================================================================
set -euo pipefail

PROVIDER="${1:-gke}"

echo "============================================================"
echo " Cloud Workload Modernization Platform Bootstrapper"
echo " Target Environment: ${PROVIDER}"
echo " Current Context: $(kubectl config current-context 2>/dev/null || echo 'default')"
echo "============================================================"

# 1. Validate Prerequisites
for cmd in kubectl helm git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[!] Error: Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

echo "[*] Verifying cluster connectivity..."
kubectl cluster-info >/dev/null

# 2. Create Core Namespaces
echo "[*] Creating core platform namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace demo-workload --dry-run=client -o yaml | kubectl apply -f -

# 3. Label Namespaces for Policy & Metrics
echo "[*] Applying namespace metadata labels..."
kubectl label namespace demo-workload tenant=demo --overwrite
kubectl label namespace demo-workload pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label namespace demo-workload pod-security.kubernetes.io/audit=restricted --overwrite
kubectl label namespace demo-workload pod-security.kubernetes.io/warn=restricted --overwrite

# 4. Check Calico CNI on GKE cluster
if ! kubectl get crd globalnetworkpolicies.projectcalico.org &>/dev/null; then
  echo "[!] Notice: Calico CRDs (projectcalico.org) not detected on this cluster."
  echo "    Ensure Calico network policy is enabled on your GKE cluster or install Tigera operator:"
  echo "    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml"
  echo "    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml"
else
  echo "[+] Calico GlobalNetworkPolicy CRD detected and ready."
fi

# 5. Install ArgoCD
echo "[*] Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "[*] Waiting for ArgoCD server deployment to roll out..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || true

# 5. Apply GitOps Root Application
echo "[*] Applying GitOps Root Application (App-of-Apps)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

kubectl apply -f "${REPO_ROOT}/kubernetes/gitops/bootstrap/root-application.yaml"

echo "============================================================"
echo "[+] Platform bootstrap sequence initiated successfully."
echo "    Monitor ArgoCD status: kubectl get applications -n argocd"
echo "============================================================"
