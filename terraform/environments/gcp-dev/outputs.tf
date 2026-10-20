output "cluster_name" {
  description = "GKE Cluster Name"
  value       = module.gke_platform.cluster_name
}

output "cluster_endpoint" {
  description = "GKE Cluster Endpoint"
  value       = module.gke_platform.cluster_endpoint
}

output "configure_kubectl" {
  description = "Command to authenticate kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke_platform.cluster_name} --region ${var.region} --project ${var.project_id}"
}
