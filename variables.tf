# variables.tf
variable "ssh_public_key" {
  description = "Public Key string for VM access"
  type        = string
}
variable "gcp_project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "rancher_url" {
  description = "Rancher Server URL"
  type        = string
}

variable "rancher_access_key" {
  description = "Rancher Access Key"
  type        = string
  sensitive   = true
}

variable "rancher_secret_key" {
  description = "Rancher Secret Key"
  type        = string
  sensitive   = true
}

variable "workload_kubernetes_version" {
  description = "Kubernetes version for RKE2"
  type        = string
  default     = "v.1.33.6+rke2r1" # ใส่ค่า Default ไว้กันเหนียว
}