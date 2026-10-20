module "eks_platform" {
  source = "../../modules/aws"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_cidr            = var.vpc_cidr
  node_instance_types = var.node_instance_types
  desired_capacity    = var.desired_capacity
  min_capacity        = var.min_capacity
  max_capacity        = var.max_capacity

  tags = {
    Environment = "dev"
    Platform    = "cloud-workload-modernization"
  }
}
