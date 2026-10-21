# End-to-End Architecture Overview

## 1. Executive Summary
The **Cloud Workload Modernization Platform** establishes an enterprise-grade reference architecture for migrating legacy on-premise workloads to Google Cloud managed Kubernetes (GCP GKE). The platform incorporates:
- **Declarative Infrastructure as Code (IaC)** using modular Terraform for GKE.
- **Continuous Delivery via GitOps** using ArgoCD App-of-Apps pattern.
- **Zero-Trust Networking** enforced through Calico GlobalNetworkPolicies on GKE.
- **Shift-Left Static Analysis** via automated Checkov and Trivy CI gates.
- **Runtime Threat Detection & Automated Remediation** using Falco and Falco Talon.

---

## 2. High-Level Architecture Diagram

```mermaid
graph TB
    subgraph CI/CD ["Shift-Left CI & GitOps"]
        GH[GitHub Actions: Checkov + Trivy] --> Repo[Git Repository]
        Repo --> ArgoCD[ArgoCD Bootstrap Engine]
    end

    subgraph Infrastructure ["GCP Terraform Layer"]
        TF_GCP[Terraform GCP Module] --> GKE[GCP Private GKE + Workload Identity]
    end

    subgraph KubernetesPlatform ["Platform Layer"]
        ArgoCD --> PlatformApps[Declarative Platform Apps]
        PlatformApps --> Ingress[Ingress Controller: GKE Ingress / GCE]
        PlatformApps --> Obs[Prometheus + Alertmanager]
        PlatformApps --> SecStack[Security Stack]
    end

    subgraph SecurityRuntime ["Runtime Defense & Remediation"]
        SecStack --> Calico[Calico CNI / NetworkPolicy Engine]
        SecStack --> Falco[Falco eBPF Kernel Probe]
        Falco -->|Alert Stream (gRPC/HTTP)| Talon[Falco Talon Engine]
        Talon -->|Remediate Action (Pod Quarantine/Kill)| K8sAPI[Kubernetes Control Plane API]
    end

    subgraph Workloads ["Application Layer"]
        Demo[Multi-Tenant Demo Service]
        Sim[Attacker Simulation Probe]
    end

    Calico -.->|Micro-segmentation| Demo
    Falco -.->|System Call Tracing| Demo
    Falco -.->|Anomaly Detection| Sim
```

---

## 3. Platform Pillars

### 3.1 Infrastructure as Code (Terraform)
- **GCP Module**: Configures a custom VPC, Private GKE cluster with authorized networks, Shielded GKE nodes (Container-Optimized OS), and Google Workload Identity bindings.

### 3.2 GitOps Delivery (ArgoCD)
- Implements the **App-of-Apps** pattern.
- Separates infrastructure manifests (`kubernetes/platform`), security controls (`kubernetes/security`), and workload definitions (`kubernetes/workloads`).
- Supports self-healing, automated drift detection, and out-of-sync notifications.

### 3.3 Zero-Trust Network Microsegmentation (Calico)
- Deny-all default ingress/egress policies across tenant namespaces.
- Dynamic quarantine policies triggered during incident escalation to isolate compromised pods without deleting forensic evidence.

### 3.4 Runtime Observability & Active Response
- **Falco**: Monitors Linux syscalls (via eBPF driver) against MITRE ATT&CK container evasion and privilege escalation rules.
- **Falco Talon**: Consumes Falco events and executes sub-second remediation (pod quarantine via network label patching, termination, or cordoning nodes).
