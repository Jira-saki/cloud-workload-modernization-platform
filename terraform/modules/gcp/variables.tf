variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
  default     = "modernization-gke-dev"
}

variable "subnet_cidr" {
  description = "Subnet CIDR for primary nodes"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR for pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for services"
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master control plane"
  type        = string
  default     = "172.16.0.0/28"
}

variable "machine_type" {
  description = "Compute instance machine type"
  type        = string
  default     = "e2-standard-4"
}

variable "initial_node_count" {
  description = "Initial number of nodes per zone"
  type        = number
  default     = 2
}
