# Cloud Workload Modernization Platform
> **Enterprise Reference Architecture & Blueprint for Zero-Trust Multi-Tenant Cloud Migration**

[English](README.md) | [日本語 (Japanese)](README.jp.md)

---

[![IaC Security: Checkov](https://img.shields.io/badge/IaC%20Security-Checkov%20Passed-brightgreen)](https://github.com/bridgecrewio/checkov)
[![Container Security: Trivy](https://img.shields.io/badge/Vulnerability%20Scan-Trivy%20Enforced-blue)](https://github.com/aquasecurity/trivy)
[![GitOps: ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD%20Sync-orange)](https://argo-cd.readthedocs.io/)
[![Runtime Security: Falco](https://img.shields.io/badge/Runtime%20Defense-Falco%20eBPF-purple)](https://falco.org/)

---

## 1. Executive Summary & Architectural Motivation

This repository serves as a sanitized, production-ready enterprise reference implementation designed to address the systemic operational toils and security failure modes of legacy shared hosting environments. 

### The Real-World Engineering Problem (Legacy Failure Modes)
In traditional shared web infrastructure hosting multi-tenant workloads (20+ public domains), real-world security incidents revealed critical systemic vulnerabilities:
* **Zombie Persistence & Self-Healing Malware:** Background watchdog processes continuously respawning web shells and malicious configurations (`index.php`, `.htaccess`) upon file deletion.
* **Privilege Abuse & Immutable File Locking:** Threat actors leveraging Linux file system attributes (`chattr +i`, `chmod 0000`) to create unkillable root-level footholds, blocking incident response engineers.
* **Unrestricted Lateral Movement:** Symlink traversals and shared execution permissions allowing cross-tenant contamination from a single "Patient Zero" domain to adjacent tenant workloads.
* **Outbound Command & Control (C2):** Compromised worker processes initiating unauthorized egress connections to external command-and-control servers.

### The Cloud-Native Architectural Solution
To eliminate these risks at the root-cause level, this platform implements a modernized, zero-trust cloud foundation:
* **Immutable Infrastructure:** AWS Bottlerocket OS / GCP Container-Optimized OS (COS) providing read-only root filesystems—eliminating persistent malware footholds and disabling direct SSH access.
* **Kernel-Level eBPF Threat Detection:** Modern eBPF probes via **Falco** (`driver.kind: modern_ebpf`) capturing unauthorized syscalls (`execve`, shell spawns, privilege escalation) with zero kernel overhead.
* **Sub-Second Closed-Loop Remediation:** An automated response loop (**Falco $\rightarrow$ Falcosidekick $\rightarrow$ Falco Talon**) dynamically labeling compromised pods (`quarantine=true`) and executing sub-second pod termination (`grace_period: 0s`), enabling automated self-healing without manual human intervention.
* **Micro-Segmented Multi-Tenancy:** **Calico CNI** / Cloud Dataplane V2 enforcing strict default-deny policies, completely terminating lateral movement vectors.

---

## 2. High-Level Architecture

```text
                           [ External Ingress Traffic ]
                                        │
                                        ▼
                  [ Cloud Load Balancer / WAF Enforcement ]
                                        │
┌───────────────────────────────────────┼───────────────────────────────────────┐
│ Kubernetes Platform (EKS / GKE / KVM) │                                       │
│                                       ▼                                       │
│                         [ Micro-Segmented Tenant Pod ]                        │
│                                       │                                       │
│   (Compromised Worker / Unauthorized  │ (Syscall: execve /bin/sh)             │
│    Outbound C2 Attempt)               ▼                                       │
│                         [ Linux Kernel (modern_ebpf) ]                        │
│                                       │                                       │
│                                       ▼                                       │
│                        [ Falco Threat Detection Engine ]                      │
│                                       │                                       │
│                                       ▼ (gRPC / HTTPS Webhook)                │
│                            [ Falcosidekick Router ]                           │
│                                       │                                       │
│                                       ▼                                       │
│                        [ Falco Talon Automated Action ]                       │
│                                 │          │                                  │
│       ┌─────────────────────────┘          └─────────────────────────┐        │
│       ▼ (Action 1: Immediate Isolation)                              ▼        │
│  [ Action: kubernetes:labelize ]                       [ Action: kubernetes:terminate ]
│  [ Patch Label: quarantine=true ]                      [ Pod Terminated (0s) ]│
│       │                                                              │        │
│       ▼                                                              ▼        │
│  [ Calico Quarantine Policy ]                             [ ReplicaSet Healing]
│  * Drops ALL Ingress & Egress                             * Spawns clean pod  │
│  * Execution Isolated in < 1s                             * Zero downtime     │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Technology Stack & Multi-Cloud Implementation

| Domain | Cloud-Agnostic Baseline | AWS Implementation | GCP Implementation |
| :--- | :--- | :--- | :--- |
| **IaC Orchestration** | Terraform 1.6+ (Modular) | AWS Provider (VPC, KMS CMK, EKS) | Google Provider (VPC, Cloud NAT, GKE) |
| **Node Security** | Immutable Minimal OS | AWS Bottlerocket OS (No SSH) | Container-Optimized OS (Shielded GKE) |
| **Identity & Access** | Workload Identity Federation | AWS IAM Roles for Service Accounts (IRSA) | GKE Workload Identity |
| **Network Policy** | Zero-Trust Microsegmentation | Calico CNI (Default-Deny) | Dataplane V2 (eBPF Native) |
| **Runtime Detection** | eBPF Kernel Tracing | Falco (`driver.kind: modern_ebpf`) | Falco (`driver.kind: modern_ebpf`) |
| **Remediation Loop** | Automated Event-Driven Action | Falco Talon Response Engine | Falco Talon Response Engine |
| **Continuous Delivery** | Declarative GitOps | ArgoCD (Pull Model) | ArgoCD (Pull Model) |
| **Shift-Left Security** | CI Pre-Merge Static Scanning | Checkov (IaC) & Trivy (Manifests) | Checkov (IaC) & Trivy (Manifests) |

---

## 4. Shift-Left CI/CD & GitOps Delivery

```text
[ Developer Commit ] ──► [ Pull Request ]
                                │
                                ▼
        [ GitHub Actions: Shift-Left Security Gate ]
          ├── Checkov: Static Analysis on Terraform Modules (KMS, IMDSv2)
          └── Trivy: Vulnerability & Misconfiguration Scanner
                                │
                       (Pass All Gates)
                                ▼
                        [ Merge to main ]
                                │
                                ▼ (Pull Reconcile Loop)
                      [ ArgoCD In-Cluster ]
                                │
                                ▼
               [ Deployed EKS / GKE / KVM Clusters ]
```

---

## 5. Repository Directory Layout

```text
cloud-workload-modernization-platform/
├── .github/
│   └── workflows/
│       └── shift-left-security.yaml      # Checkov & Trivy automated pipeline
├── docs/
│   ├── architecture-overview.md          # End-to-end design specifications
│   ├── threat-model.md                   # Formal threat model & mitigation map
│   └── local-install-runbook.md          # Local Ubuntu KVM setup & verification runbook
├── kubernetes/
│   ├── gitops/
│   │   ├── bootstrap/                    # ArgoCD root application (App-of-Apps)
│   │   └── apps/                         # Declarative platform components
│   ├── platform/
│   │   ├── ingress/                      # AWS LBC / GCP Ingress controllers
│   │   └── observability/                # Prometheus & Alertmanager configs
│   ├── security/
│   │   ├── calico/                       # Calico GlobalNetworkPolicy & quarantine
│   │   ├── falco/                        # Falco values & custom detection rules
│   │   └── falco-talon/                  # Automated remediation configurations
│   └── workloads/
│       ├── demo-app/                     # Sanitized multi-tenant demo service
│       └── attacker-simulation/          # Controlled exploit simulation probe
├── scripts/
│   ├── bootstrap-platform.sh             # Cluster initialization script
│   └── verify-remediation.sh             # Threat detection verification test
└── terraform/
    ├── environments/
    │   ├── aws-dev/                      # Environment entry point for AWS
    │   └── gcp-dev/                      # Environment entry point for GCP
    └── modules/
        ├── aws/                          # AWS VPC, EKS, Bottlerocket, IRSA, KMS CMK
        └── gcp/                          # GCP Custom VPC, Private GKE, Workload Identity
```

---

## 6. Incident Remediation Operational SLA Targets

| Metric | Legacy Shared Hosting (Observed) | Modernized Cloud Platform (Target) |
| :--- | :--- | :--- |
| **Threat Detection Latency** | Days / Weeks (Manual inspection, audit) | **< 100 milliseconds** (eBPF syscall event) |
| **Network Quarantine Time** | Hours (Manual `.htaccess` edit / port blocking) | **< 1.0 second** (Automated dynamic Calico policy) |
| **Compromised Asset Containment** | Hours / Days (Manual SSH `chmod` / `rm -rf`) | **< 2.0 seconds** (Automated pod kill & clean respawn) |
| **Human Toil per Incident** | High (Engineering manual forensic labor) | **Zero Toil** (Fully automated closed loop) |

---

## 7. Quickstart & Deployment Options

### Option A: Local Testing on Ubuntu KVM (Recommended First Step)
For running and validating the entire security and remediation stack on a local Ubuntu KVM or bare-metal cluster without cloud costs, follow our dedicated step-by-step guide:
👉 **[Local Cluster Installation & Verification Runbook](docs/local-install-runbook.md)**

```bash
# 1. Initialize cluster namespaces and ArgoCD
./scripts/bootstrap-platform.sh local

# 2. Run automated sub-second remediation verification
./scripts/verify-remediation.sh
```

---

### Option B: Multi-Cloud Infrastructure (AWS / GCP)

#### AWS EKS Deployment
```bash
cd terraform/environments/aws-dev
terraform init
terraform plan
terraform apply
```

#### GCP GKE Deployment
```bash
cd terraform/environments/gcp-dev
terraform init
terraform plan
terraform apply
```

---

## 8. Verification & Attack Simulation

To validate the sub-second threat containment engine, execute the automated verification script:

```bash
./scripts/verify-remediation.sh
```

### Telemetry & Output Sequence
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
[!] Kernel Event: Syscall execve(/bin/sh) intercepted by Falco modern_ebpf driver.
[!] Alert dispatched to Falcosidekick -> Falco Talon webhook.
[*] Action Triggered: kubernetes:labelize -> Applied 'quarantine=true' in 240ms.
[*] Action Triggered: Calico GlobalNetworkPolicy active -> All network traffic DROPPED.
[*] Action Triggered: kubernetes:terminate -> Pod terminated (grace_period=5s).
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

## 9. Compliance & Sanitization Disclaimer

This repository represents a clean-room architectural reference implementation. All company identities, proprietary credentials, real-world domain records, and customer data have been completely removed and replaced with vendor-neutral mock definitions.