output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks_platform.cluster_name
}

output "cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = module.eks_platform.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.eks_platform.vpc_id
}

output "configure_kubectl" {
  description = "Command to authenticate kubectl"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks_platform.cluster_name}"
}
