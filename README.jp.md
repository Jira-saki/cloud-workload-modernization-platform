# クラウドワークロード近代化プラットフォーム (Cloud Workload Modernization Platform)
> **Google Kubernetes Engine (GKE) 上でのゼロトラスト・マルチテナント運用のためのエンタープライズ・リファレンスアーキテクチャ**

[English](README.md) | [日本語 (Japanese)](README.jp.md)

---

[![IaC Security: Checkov](https://img.shields.io/badge/IaC%20Security-Checkov%20Passed-brightgreen)](https://github.com/bridgecrewio/checkov)
[![Container Security: Trivy](https://img.shields.io/badge/Vulnerability%20Scan-Trivy%20Enforced-blue)](https://github.com/aquasecurity/trivy)
[![GitOps: ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD%20Sync-orange)](https://argo-cd.readthedocs.io/)
[![Runtime Security: Falco](https://img.shields.io/badge/Runtime%20Defense-Falco%20eBPF-purple)](https://falco.org/)

---

## 1. エグゼクティブサマリー & アーキテクチャの動機

本リポジトリは、**Google Kubernetes Engine (GKE)** 上で動作し、従来の共有ホスティング環境における構造的な運用負荷およびセキュリティ障害モードを根本解決するために設計された、サニタイズ済みの本番仕様エンタープライズ・リファレンス実装です。

### 従来のレガシー環境における課題（実世界のインシデント要因）
多数のマルチテナント・ワークロード（20以上のパブリックドメイン）を抱える従来の共有サーバー基盤では、以下のような致命的な脆弱性が顕在化していました：
* **ゾンビ化する永続マルウェアと自己修復ウォッチドッグ:** ファイル削除を検知してWebシェルや悪意のある設定ファイル（`index.php`、`.htaccess`）を即座に再生成するバックグラウンド監視プロセス。
* **特権の悪用と不変ファイルロック:** Linuxの拡張ファイル属性（`chattr +i`、`chmod 0000`）を悪用し、root権限でも削除不能な足場を構築、インシデント対応を妨害。
* **無制限の横方向への移動（ラテラルムーブメント）:** シンボリックリンクの走査や共有グループ権限の悪用により、1つの侵害されたドメイン（Patient Zero）から隣接する他テナントへ感染が拡大。
* **不正な外部C2（Command & Control）通信:** 侵害されたワーカープロセスが外部の悪意あるC2サーバーへ不正なアウトバウンド通信を確立。

### クラウドネイティブな解決アプローチ
本プラットフォームは、これらのリスクを根本から排除するため、GKE 上にゼロトラストに基づく近代的な基盤を確立します：
* **イミュータブル（不変）インフラストラクチャ:** Container-Optimized OS (COS) を搭載した Shielded GKE ノード（セキュアブート有効）と読み取り専用ルートファイルシステム（Read-only Root FS）を採用。不正な永続マルウェアの侵入を防ぎ、SSH直接ログインを無効化。
* **カーネルレベルのeBPF脅威検知:** **Falco**（`driver.kind: modern_ebpf`）により、カーネルのオーバーヘッドなしに不正なシステムコール（`execve`、シェル起動、権限昇格）をリアルタイム検知。
* **1秒未満の自動修復ループ（Closed-Loop Remediation）:** 自動応答パイプライン（**Falco $\rightarrow$ Falcosidekick $\rightarrow$ Falco Talon**）が侵害されたPodに即座に`quarantine=true`ラベルを付与し、1秒未満で強制終了（`grace_period: 0s`）。人手による介入なしでセルフヒーリングを実行。
* **マイクロセグメンテーションによるマルチテナンシー:** **GKE Calico Network Policy** により厳格なDefault-Denyポリシーを適用し、横方向への侵害経路を完全遮断。

---

## 2. システムアーキテクチャ概要

```text
                           [ 外部からのIngressトラフィック ]
                                        │
                                        ▼
                   [ クラウドLoad Balancer / Cloud Armor WAF ]
                                        │
┌───────────────────────────────────────┼───────────────────────────────────────┐
│ Kubernetes Platform (GCP GKE)         │                                       │
│                                       ▼                                       │
│                         [ 分離されたテナントPod ]                             │
│                                       │                                       │
│   (侵害されたワーカー / 不正な        │ (システムコール: execve /bin/sh)      │
│    アウトバウンドC2通信の試行)        ▼                                       │
│                         [ Linux Kernel (modern_ebpf) ]                        │
│                                       │                                       │
│                                       ▼                                       │
│                         [ Falco 脅威検知エンジン ]                            │
│                                       │                                       │
│                                       ▼ (gRPC / HTTPS Webhook)                │
│                            [ Falcosidekick Router ]                           │
│                                       │                                       │
│                                       ▼                                       │
│                        [ Falco Talon 自動修復アクション ]                     │
│                                 │          │                                  │
│       ┌─────────────────────────┘          └─────────────────────────┐        │
│       ▼ (Action 1: 即時ネットワーク隔離)                              ▼        │
│  [ Action: kubernetes:labelize ]                       [ Action: kubernetes:terminate ]
│  [ ラベル付与: quarantine=true ]                       [ Pod強制終了 (0秒) ]  │
│       │                                                              │        │
│       ▼                                                              ▼        │
│  [ Calico Quarantine Policy ]                             [ ReplicaSet自動修復]
│  * すべてのIngress/Egressを破棄                           * 新しい正常Podを起動│
│  * 1秒未満でネットワーク隔離完了                          * ダウンタイムゼロ  │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 技術スタック & GKE 実装仕様

| 領域 | クラウドネイティブ・ベースライン | GKE 本番実装仕様 |
| :--- | :--- | :--- |
| **IaC オーケストレーション** | Terraform 1.6+（モジュール設計） | Google Provider（VPC, Cloud NAT, Private GKE） |
| **ノードセキュリティ** | イミュータブル最小構成OS | Container-Optimized OS（Shielded GKE, セキュアブート） |
| **ID & アクセス管理** | ワークロードIDフェデレーション | GKE Workload Identity & GKE メタデータサーバー |
| **ネットワークポリシー** | ゼロトラスト・マイクロセグメンテーション | Calico NetworkPolicy（Default-Deny Ingress/Egress） |
| **ランタイム脅威検知** | eBPF カーネルトレーシング | Falco（`driver.kind: modern_ebpf`） |
| **自動修復ループ** | イベント駆動型自動アクション | Falco Talon レスポンスエンジン |
| **継続的デリバリー** | 宣言的 GitOps | ArgoCD（App-of-Apps パターン） |
| **シフトレフトセキュリティ** | CIプリマージ静的スキャン | Checkov（IaC CIS ベンチマーク）& Trivy（脆弱性検知） |

---

## 4. シフトレフト CI/CD & GitOps デリバリー

```text
[ 開発者のコミット ] ──► [ プルリクエスト (PR) ]
                                │
                                ▼
        [ GitHub Actions: シフトレフト・セキュリティゲート ]
          ├── Checkov: Terraformモジュールの静的解析 (CIS GCP ベンチマーク)
          └── Trivy: コンテナ脆弱性 & K8s構成ミスのスキャン
                                │
                        (全テスト合格)
                                ▼
                        [ main へマージ ]
                                │
                                ▼ (自動同期ループ)
                      [ クラスター内 ArgoCD ]
                                │
                                ▼
                       [ デプロイ先: GKE クラスター ]
```

---

## 5. リポジトリ構成

```text
cloud-workload-modernization-platform/
├── .github/
│   └── workflows/
│       └── shift-left-security.yaml      # Checkov & Trivy 自動化パイプライン
├── docs/
│   ├── architecture-overview.md          # アーキテクチャ設計仕様書
│   └── threat-model.md                   # 脅威モデル & 対策マッピング (STRIDE)
├── kubernetes/
│   ├── gitops/
│   │   ├── bootstrap/                    # ArgoCD ルートアプリケーション (App-of-Apps)
│   │   └── apps/                         # 宣言的プラットフォームコンポーネント
│   ├── platform/
│   │   ├── ingress/                      # GKE Ingress コントローラー設定
│   │   └── observability/                # Prometheus & Alertmanager 設定
│   ├── security/
│   │   ├── calico/                       # Calico GlobalNetworkPolicy & 隔離ポリシー
│   │   ├── falco/                        # Falco values & カスタム検知ルール
│   │   └── falco-talon/                  # 自動修復エンジン設定 (Talon)
│   └── workloads/
│       ├── demo-app/                     # サニタイズ済みマルチテナント・デモサービス
│       └── attacker-simulation/          # 攻撃シミュレーション・検証用プローブ
├── scripts/
│   ├── bootstrap-platform.sh             # クラスター初期化スクリプト
│   └── verify-remediation.sh             # 脅威検知・自動修復検証スクリプト
└── terraform/
    ├── environments/
    │   └── gcp-dev/                      # GCP 向け環境エントリーポイント
    └── modules/
        └── gcp/                          # GCP カスタムVPC, Private GKE, Workload Identity
```

---

## 6. インシデント修復における運用SLA目標値

| 測定メトリクス | 従来の共有サーバー（実績値） | 近代化クラウド基盤（目標値） |
| :--- | :--- | :--- |
| **脅威検知レイテンシ** | 数日〜数週間（人手による調査・監査） | **100ミリ秒未満**（eBPFシステムコール検知） |
| **ネットワーク隔離時間** | 数時間（`.htaccess`の手動編集 / ポート遮断） | **1.0秒未満**（Calico動的ポリシー適用） |
| **侵害資産の封じ込め** | 数時間〜数日（SSH経由の`chmod` / `rm -rf`） | **2.0秒未満**（Pod自動終了 & クリーン再起動） |
| **インシデントあたりの運用負荷** | 極めて高い（手作業によるフォレンジック） | **ゼロ負荷**（完全自動化された修復ループ） |

---

## 7. クイックスタート & デプロイ手順 (GCP GKE)

**前提条件:** 課金が有効で Kubernetes Engine / Compute Engine API を有効化した GCP プロジェクト、`gcloud`・`terraform` (>= 1.6)・`kubectl`・`helm` のインストール、および `gcloud auth application-default login` による認証。`terraform.tfvars.example` を `terraform.tfvars` にコピーし、`project_id` を設定してください。

### ステップ 1: Terraform による GKE 基盤のプロビジョニング
```bash
cd terraform/environments/gcp-dev
terraform init
terraform plan
terraform apply
```

### ステップ 2: kubectl の GKE クラスター接続設定
```bash
gcloud container clusters get-credentials modernization-gke-dev --region us-central1 --project <YOUR_GCP_PROJECT_ID>
```

### ステップ 3: プラットフォーム基盤および GitOps のブートストラップ
```bash
# リポジトリのルートディレクトリから実行
./scripts/bootstrap-platform.sh gke
```

### ステップ 4: 1秒未満の自動修復・脅威封じ込めテストを実行
GKE クラスターに対して `./scripts/verify-remediation.sh` を実行します（セクション 8 参照）。

---

## 8. 攻撃シミュレーションと検証

1秒未満の脅威封じ込めエンジンを検証するには、GKE クラスターのコンテキストに対して自動テストスクリプトを実行します：

```bash
./scripts/verify-remediation.sh
```

### 実行結果とテレメトリ出力例
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

## 9. コンプライアンス & サニタイズ免責事項

本リポジトリは、クリーンルーム環境で構築されたアーキテクチャ・リファレンス実装です。実在する企業名、機密認証情報、本番ドメインレコード、および顧客データはすべて完全に除去され、ベンダーニュートラルなモック定義に置き換えられています。
