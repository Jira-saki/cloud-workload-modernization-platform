module "gke_platform" {
  source = "../../modules/gcp"

  project_id             = var.project_id
  region                 = var.region
  cluster_name           = var.cluster_name
  subnet_cidr            = var.subnet_cidr
  pods_cidr              = var.pods_cidr
  services_cidr          = var.services_cidr
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
  machine_type           = var.machine_type
  initial_node_count     = var.initial_node_count
}
