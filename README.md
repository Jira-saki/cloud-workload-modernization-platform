# Cloud Workload Modernization Platform
> **Enterprise Reference Architecture & Blueprint for Zero-Trust Multi-Tenant Cloud Migration**

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
* **Unrestricted Lateral Movement:** Symlink traversals and shared execution permissions allowing cross-tenant contamination from a single "Patient Zero" domain to isolated tenants.
* **Outbound Command & Control (C2):** Compromised worker processes initiating unauthorized egress connections to external command-and-control servers.

### The Cloud-Native Architectural Solution
To eliminate these risks at the root-cause level, this platform implements a modernized, zero-trust cloud foundation:
* **Immutable Infrastructure:** AWS Bottlerocket OS / GCP Container-Optimized OS (COS) providing read-only root filesystems—eliminating persistent malware footholds and disabling direct SSH access.
* **Kernel-Level eBPF Threat Detection:** Modern eBPF probes via **Falco** to capture unauthorized syscalls (`execve`, shell spawns, privilege escalation) with zero kernel overhead.
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
│ Kubernetes Platform (EKS / GKE)       │                                       │
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
│  [ Patch Label: quarantine=true ]                           [ Delete Pod: 0s ]│
│       │                                                              │        │
│       ▼                                                              ▼        │
│  [ Calico Quarantine Policy ]                             [ ReplicaSet Healing]
│  * Drops ALL Ingress & Egress                             * Spawns clean pod  │
│  * Execution Isolated in < 1s                             * Zero downtime     │
└───────────────────────────────────────────────────────────────────────────────┘
3. Technology Stack & Multi-Cloud ImplementationDomainCloud-Agnostic BaselineAWS ImplementationGCP ImplementationIaC OrchestrationTerraform 1.5+ (Modular)AWS Provider (VPC, KMS, EKS)Google Provider (VPC, Cloud NAT, GKE)Node SecurityImmutable Minimal OSAWS Bottlerocket OS (No SSH)Container-Optimized OS (Shielded GKE)Identity & AccessWorkload Identity FederationAWS IAM Roles for Service Accounts (IRSA)GKE Workload IdentityNetwork PolicyZero-Trust MicrosegmentationCalico CNI (Default-Deny)Dataplane V2 (eBPF Native)Runtime DetectioneBPF Kernel TracingFalco (modern_ebpf probe)Falco (modern_ebpf probe)Remediation LoopAutomated Event-Driven ActionFalco Talon Response EngineFalco Talon Response EngineContinuous DeliveryDeclarative GitOpsArgoCD (Pull Model)ArgoCD (Pull Model)Shift-Left SecurityCI Pre-Merge Static ScanningCheckov (IaC) & Trivy (Manifests)Checkov (IaC) & Trivy (Manifests)4. Shift-Left CI/CD & GitOps DeliveryPlaintext[ Developer Commit ] ──► [ Pull Request ]
                               │
                               ▼
        [ GitHub Actions: Shift-Left Security Gate ]
          ├── Checkov: Static Analysis on Terraform Modules
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
                  [ Deployed EKS / GKE Clusters ]
5. Repository Directory LayoutPlaintextcloud-workload-modernization-platform/
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
        ├── aws/                          # AWS VPC, EKS, Bottlerocket, IRSA
        └── gcp/                          # GCP Custom VPC, Private GKE, Workload Identity
6. Verification & Attack SimulationTo validate the sub-second threat containment engine, run the verification script:Bash# Execute the exploit simulation script against the sandbox workload
./scripts/verify-remediation.sh
Expected Telemetry Output:Plaintext[+] Spawning controlled terminal shell inside workload: demo-app-6f8b89c7d-x9z12
[!] Kernel Event: Syscall execve(/bin/sh) intercepted by Falco modern_ebpf driver.
[!] Alert dispatched to Falcosidekick -> Falco Talon webhook.
[*] Action Triggered: kubernetes:labelize -> Applied 'quarantine=true' in 0.28s.
[*] Action Triggered: Calico GlobalNetworkPolicy active -> All network traffic DROPPED.
[*] Action Triggered: kubernetes:terminate -> Pod terminated (grace_period=0s).
[+] ReplicaSet self-healing reconciled: Fresh uncompromised pod demo-app-6f8b89c7d-k4w89 ready.
[SUCCESS] Attack neutralized in 0.72 seconds. Zero persistent foothold established.
7. Compliance & Sanitization DisclaimerThis repository represents a clean-room architectural reference implementation. All company identities, proprietary credentials, real-world domain records, and customer data have been completely removed and replaced with vendor-neutral mock definitions.
---

### 2. ไฟล์ `docs/threat-model.md`

```markdown
# Threat Model & Security Architecture Baseline

## 1. Context & Scope
This threat model analyzes the structural transition from legacy shared hosting architectures (hosting multi-tenant PHP/WordPress workloads) to an enterprise-grade, hardened container orchestration platform running on AWS EKS and GCP GKE.

The analysis is based on STRIDE methodology and validated against observed attack patterns recorded during production incident remediation efforts.

---

## 2. Target Threat Profiles (Observed Attack Vectors)

### Threat Vector 1: Zombie Persistence & Self-Healing Watchdogs
* **Observed Mechanism:** Attackers injected background guardian processes monitoring file modification events on `index.php`, `.htaccess`, and `header.php`. When system administrators removed malicious artifacts, the watchdog regenerated them immediately.
* **Impact:** System restoration via manual file deletion is impossible without terminating underlying hidden system processes.

### Threat Vector 2: Filesystem Attribute Hijacking (Immutable Locking)
* **Observed Mechanism:** Exploits utilized elevated capabilities to set immutable attributes (`chattr +i`) or stripped permissions (`chmod 0000`, `d---------`) across system directories, creating root-level persistence and causing "Permission Denied" errors during remediation.
* **Impact:** Remediation blockage; denial of administrative control.

### Threat Vector 3: Lateral Movement via Shared Filesystem & Symlinks
* **Observed Mechanism:** A single initial compromised tenant ("Patient Zero") executed symbolic link traversal (`ln -s`) and leveraged shared group access permissions to propagate web shells across adjacent customer domains hosted within the same execution boundary.
* **Impact:** Total account compromise across 20+ independent workloads.

### Threat Vector 4: Outbound Command & Control (C2) & Web Shell Infiltration
* **Observed Mechanism:** Deployment of interactive web shells (`Gecko Shell`, obfuscated PHP droppers) executing reverse shells and establishing persistent outbound connections to malicious external IP addresses/domains to retrieve secondary payloads.
* **Impact:** Data exfiltration, SEO poisoning, and inclusion in distributed botnet clusters.

---

## 3. Threat Mitigation Matrix (STRIDE Mapping)

| Threat Category (STRIDE) | Attack Mechanism (Legacy) | Cloud-Native Architectural Countermeasure | Verification / Enforcing Component |
| :--- | :--- | :--- | :--- |
| **Tampering** | Overwriting `.htaccess` and `index.php` with self-healing payloads | **Read-Only Root Filesystem:** Pod containers run with `readOnlyRootFilesystem: true`. Node instances execute on immutable OS (Bottlerocket / COS). | Kubernetes SecurityContext & OS Kernel |
| **Elevation of Privilege** | Setting `chattr +i` and tampering with Linux file attributes | **Dropped Linux Capabilities:** Drop `ALL` capabilities; explicitly prevent `CAP_LINUX_IMMUTABLE` and `CAP_SYS_ADMIN`. Set `allowPrivilegeEscalation: false`. | Admission Controller (Kyverno / OPA) |
| **Information Disclosure** | Reading plaintext database passwords and secrets from configuration files | **Secret Decoupling & Envelope Encryption:** Secrets managed in AWS Secrets Manager / GCP Secret Manager, protected by KMS CMK, projected via External Secrets Operator. | Cloud KMS & External Secrets Operator |
| **Lateral Movement** | Symlink traversal and cross-domain filesystem contamination | **Tenant Namespace Isolation & Default-Deny:** Pods run in dedicated namespaces with Calico Default-Deny NetworkPolicies blocking cross-namespace traffic. | Calico CNI / Dataplane V2 |
| **Execution (RCE)** | Shell execution inside containers (`/bin/sh`, `/bin/bash`) | **eBPF Syscall Interception:** Falco detects runtime execution of shell binaries in container workloads via `modern_ebpf`. | Falco Engine |
| **Exfiltration** | Web shell making outbound connections to C2 domains | **Automated Sub-Second Quarantine:** Falco Talon labels pod with `quarantine=true` in < 1s, triggering Calico to drop all Ingress/Egress traffic immediately. | Falco Talon + Calico GlobalNetworkPolicy |

---

## 4. Defense-in-Depth Control Architecture

```text
Layer 1: Code & IaC (Shift-Left)
  ├── Checkov (Terraform security validation, enforce KMS, private endpoints)
  └── Trivy (Container vulnerability scanner, K8s misconfiguration checks)

Layer 2: Cloud Infrastructure Foundation (IaC)
  ├── Private Cluster Endpoints (EKS/GKE master & nodes strictly isolated)
  ├── Workload Identity / IRSA (No permanent cloud IAM keys stored on workloads)
  └── Immutable Node OS (AWS Bottlerocket / GCP COS with read-only root)

Layer 3: Network & Tenant Segmentation
  ├── Calico CNI / Dataplane V2
  └── Default-Deny Ingress & Egress per Namespace

Layer 4: Kernel-Level Runtime Defense & Self-Healing
  ├── Falco (modern_ebpf kernel tracepoints for zero-delay detection)
  ├── Falco Talon (Automated closed-loop remediation trigger)
  └── ReplicaSet Self-Healing (0-second grace period pod termination and respawn)
5. Incident Remediation Operational SLA TargetsMetricLegacy Shared Hosting (Observed)Modernized Cloud Platform (Target)Threat Detection LatencyDays / Weeks (Manual inspection, audit)< 100 milliseconds (eBPF syscall event)Network Quarantine TimeHours (Manual .htaccess edit / port blocking)< 1 second (Automated dynamic Calico policy)Compromised Asset ContainmentHours / Days (Manual SSH chmod / rm -rf)< 2 seconds (Automated pod kill & clean respawn)Human Toil per IncidentHigh (Engineering manual forensic labor)Zero Toil (Fully automated closed loop)