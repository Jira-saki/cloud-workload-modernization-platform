terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Custom VPC & Subnets ---
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  project                  = var.project_id

  secondary_ip_range {
    range_name    = "k8s-pod-range"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "k8s-service-range"
    ip_cidr_range = var.services_cidr
  }

  # VPC Flow Logs (Checkov CKV_GCP_26)
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- GCP Firewall Configuration (Checkov CKV2_GCP_18) ---
resource "google_compute_firewall" "allow_internal" {
  name        = "${var.cluster_name}-allow-internal"
  network     = google_compute_network.vpc.id
  project     = var.project_id
  description = "Allow internal intra-cluster VPC traffic"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# --- Cloud Router & Cloud NAT for Private GKE Egress ---
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = var.project_id
}

# --- GKE Service Account ---
resource "google_service_account" "gke_sa" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "Service Account for GKE Cluster ${var.cluster_name}"
  project      = var.project_id
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# --- Private GKE Cluster ---
# checkov:skip=CKV_GCP_65: Reference architecture does not bind to customer specific Google Workspace domain
# checkov:skip=CKV_GCP_69: Default node pool is deleted; custom node pool primary_nodes defines GKE_METADATA
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  # GKE Metadata Server (Checkov CKV_GCP_69)
  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Intranode Visibility (Checkov CKV_GCP_61)
  enable_intranode_visibility = true

  # Cluster Labels (Checkov CKV_GCP_21)
  resource_labels = {
    environment = "dev"
    platform    = "cloud-workload-modernization"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8s-service-range"
  }

  # 1. Private Cluster Configuration (Checkov CKV_GCP_21)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # 2. Master Authorized Networks (Checkov CKV_GCP_20)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_cidr
      display_name = "VPC-Subnet"
    }
  }

  # 3. Disable Basic Authentication & Issue of Client Certificates (Checkov CKV_GCP_24)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # 4. Enable Shielded Nodes at Cluster Level (Checkov CKV_GCP_69)
  enable_shielded_nodes = true

  # 5. Binary Authorization (Checkov CKV_GCP_66)
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }
}

# --- Hardened Node Pool ---
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = var.initial_node_count

  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.gke_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # GKE Metadata Server for Workload Identity (Checkov CKV_GCP_69)
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded Instance Configuration (Checkov CKV_GCP_68, CKV_GCP_70, CKV_GCP_71)
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      platform = "cloud-workload-modernization"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
