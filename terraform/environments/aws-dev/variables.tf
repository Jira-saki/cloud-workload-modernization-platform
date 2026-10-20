variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "modernization-eks-dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.100.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "desired_capacity" {
  description = "Desired worker node count"
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "Min worker node count"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Max worker node count"
  type        = number
  default     = 6
}
