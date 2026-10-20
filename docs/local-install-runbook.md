# Local Cluster (Ubuntu KVM) Installation & Verification Runbook

This runbook guides engineers through bootstrapping, configuring, and verifying the **Cloud Workload Modernization Platform** security stack on a local **Ubuntu KVM Kubernetes Cluster** before deploying to managed cloud environments (AWS EKS / GCP GKE).

---

## 1. Environment Prerequisites

### 1.1 KVM VM Specifications
| Component | Minimum Recommended Specs | Notes |
| :--- | :--- | :--- |
| **Control Plane Node** | 2 vCPU, 4 GB RAM, 30 GB Disk | Ubuntu 22.04 LTS or 24.04 LTS |
| **Worker Node(s)** | 2+ vCPU, 4-8 GB RAM, 40 GB Disk | Ubuntu 22.04 LTS or 24.04 LTS |
| **Kernel Version** | Linux Kernel >= 5.8 | Required for modern eBPF probe |
| **Container Runtime** | containerd 1.6+ or CRI-O | Standard K8s CRI |

### 1.2 Kernel eBPF & BTF Verification
Falco uses the `modern_ebpf` probe to trace container system calls without compiling kernel modules on the fly. This requires **BPF Type Format (BTF)** support in your Linux kernel.

Execute the following on your Ubuntu KVM nodes:

```bash
# 1. Verify Linux Kernel is >= 5.8
uname -r

# 2. Check that Kernel BTF debug information is available
ls -la /sys/kernel/btf/vmlinux

# Expected Output:
# -r--r--r-- 1 root root 4000000+ ... /sys/kernel/btf/vmlinux
```

> [!NOTE]
> Standard Ubuntu 22.04 LTS (Kernel 5.15 / 6.5) and 24.04 LTS (Kernel 6.8) ship with `CONFIG_DEBUG_INFO_BTF=y` enabled by default.

### 1.3 Local Tools
Ensure your local management workstation (or KVM host) has:
- `kubectl` (>= v1.28)
- `helm` (>= v3.12)
- `git`

---

## 2. Step 1: Calico CNI Installation (Required for GlobalNetworkPolicy)

The platform relies on Calico `GlobalNetworkPolicy` (`projectcalico.org/v3`) for zero-trust microsegmentation and automated pod quarantine. If your local cluster does not yet have Calico installed:

```bash
# 1. Install the Tigera Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# 2. Install Calico Custom Resources
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# 3. Wait for Calico pods to be Running
kubectl wait --namespace calico-system --for=condition=Ready pods --all --timeout=180s

# 4. Verify Calico CRDs are present
kubectl get crd globalnetworkpolicies.projectcalico.org
```

---

## 3. Step 2: Bootstrap Platform Namespaces & GitOps

Run the platform initialization script configured for local execution:

```bash
# Set your active KUBECONFIG if not using default
export KUBECONFIG=~/.kube/config

# Run bootstrap script in local mode
./scripts/bootstrap-platform.sh local
```

### What this script does:
1. Validates cluster reachability (`kubectl cluster-info`).
2. Creates core namespaces: `argocd`, `monitoring`, `falco`, and `demo-workload`.
3. Labels the tenant namespace (`demo-workload`) with `pod-security.kubernetes.io/enforce=restricted`.
4. Deploys ArgoCD and applies the GitOps root App-of-Apps manifest.

---

## 4. Step 3: Apply Calico Security Policies

Apply the base zero-trust default-deny and dynamic quarantine policies:

```bash
kubectl apply -k kubernetes/security/calico/
```

Verify policies are created:
```bash
kubectl get globalnetworkpolicies.projectcalico.org
```
*You should see `platform-default-deny-tenants` and `platform-quarantine-policy`.*

---

## 5. Step 4: Deploy Falco & Falco Talon (Security Engine)

### 5.1 Add Falco Helm Repositories
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
```

### 5.2 Deploy Falco (Modern eBPF Driver)
Deploy Falco using our hardened configuration in [values.yaml](file:///Users/mest/dev/cloud-workload-modernization-platform/kubernetes/security/falco/values.yaml):

```bash
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f kubernetes/security/falco/values.yaml
```

Check that the Falco DaemonSet is running on each node:
```bash
kubectl rollout status daemonset/falco -n falco --timeout=120s
```

### 5.3 Deploy Falco Talon (Automated Remediation Engine)
Create a ConfigMap containing the Talon remediation rules:

```bash
kubectl create configmap falco-talon-rules \
  --from-file=rules.yaml=kubernetes/security/falco-talon/rules.yaml \
  --namespace falco \
  --dry-run=client -o yaml | kubectl apply -f -
```

Deploy Falco Talon:
```bash
helm upgrade --install falco-talon falcosecurity/falco-talon \
  --namespace falco \
  -f kubernetes/security/falco-talon/values.yaml
```

Verify Talon rollout:
```bash
kubectl rollout status deployment/falco-talon -n falco --timeout=60s
```

---

## 6. Step 5: Deploy Sample Workload (Demo Service)

Deploy the multi-tenant hardened demo application:

```bash
kubectl apply -k kubernetes/workloads/demo-app/
```

Confirm the demo pods are healthy:
```bash
kubectl get pods -n demo-workload -l app.kubernetes.io/name=demo-service
```

---

## 7. Step 6: Execute Remediation Verification & Latency Test

Run the automated test suite to verify sub-second threat containment:

```bash
./scripts/verify-remediation.sh
```

### Expected Output Sequence:

```text
============================================================
 Threat Detection & Automated Remediation SLA Test
 Target Namespace: demo-workload
 SLA Threshold   : Network Severance < 1.0 Second
============================================================
[*] Step 1: Cleaning up any prior test probe...
[*] Step 2: Deploying test probe pod with network inspection utilities...
[*] Waiting for test pod to enter Ready state...

--- [PHASE 1: PRE-ATTACK CONNECTIVITY CHECK] ---
[*] Verifying baseline network access (ping 1.1.1.1)...
[+] Baseline Confirmed: Outbound egress is ACTIVE and reachable.

--- [PHASE 2: TRIGGER EXPLOIT & MEASURE REMEDIATION LATENCY] ---
[*] Initiating interactive shell session to trigger Falco detection...
[+] Quarantine label detected at +240ms!

--- [PHASE 3: POST-ATTACK VERIFICATION & LATENCY AUDIT] ---
[*] Testing post-attack network reachability from probe...
[+] Network Isolation Confirmed: 100% packet loss to external network.
------------------------------------------------------------
 Remediation Latency Measured: 240 ms (0.240s)
------------------------------------------------------------
[+++] SLA VERIFICATION PASSED: Remediation executed in 240ms (< 1.0s target)!
============================================================
[+] Verification complete.
```

---

## 8. Troubleshooting & Diagnostic Commands

### 8.1 Falco Modern eBPF Pod Fails to Start
```bash
# Check Falco pod logs
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50

# Common Cause: BTF missing
# Fix: Ensure KVM kernel is >= 5.8 and /sys/kernel/btf/vmlinux exists on worker nodes
```

### 8.2 Falco Talon Not Receiving Events
```bash
# Inspect Falcosidekick logs
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick --tail=50

# Check Falco Talon logs
kubectl logs -n falco -l app.kubernetes.io/name=falco-talon --tail=50
```

### 8.3 Calico Policy Not Blocking Traffic
```bash
# Verify policy selector matches probe labels
kubectl get globalnetworkpolicies.projectcalico.org platform-quarantine-policy -o yaml

# Inspect labels on compromised pod
kubectl get pod security-verification-probe -n demo-workload --show-labels
```

---

## 9. Cleanup Local Test Resources

To tear down test workloads while keeping platform infrastructure intact:

```bash
# Remove test pods
kubectl delete pod -n demo-workload -l app.kubernetes.io/name=verification-probe --ignore-not-found

# (Optional) Remove demo application
kubectl delete -k kubernetes/workloads/demo-app/
```
