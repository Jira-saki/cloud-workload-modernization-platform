variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "modernization-eks-dev"
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "CIDR block for the AWS VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for Bottlerocket worker nodes"
  type        = list(string)
  default     = ["t3.large"]
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Platform    = "cloud-workload-modernization"
    ManagedBy   = "terraform"
  }
}
