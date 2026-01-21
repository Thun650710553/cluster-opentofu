terraform {
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = ">= 3.0.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "rancher2" {
  api_url    = var.rancher_url
  access_key = var.rancher_access_key
  secret_key = var.rancher_secret_key
  insecure   = true
}

# 1. สร้าง Cluster V2 (RKE2)
resource "rancher2_cluster_v2" "student_project" {
  name               = "cluster"
  kubernetes_version = var.workload_kubernetes_version
  
  rke_config {
    machine_global_config = <<-EOF
      cni: "calico"
      disable-kube-proxy: false
      etcd-expose-metrics: true
    EOF
  }
   local_auth_endpoint {
    enabled = true
  }
}

# 2. สร้าง Firewall Rule
resource "google_compute_firewall" "allow_rke2" {  # ✅ ใช้ underscore
  name    = "allow-rke2"  # ชื่อจริงบน GCP ใช้ hyphen ได้
  network = "default"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "6443", "9345", "10250", "10254", "2379-2380", "30000-32767"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["8472", "4789", "30000-32767"]
  }
  
  source_ranges = ["0.0.0.0/0"]  # ⚠️ ระวัง! ควร restrict ใน production
  target_tags   = ["allow-rke2"]
}
allow {
    protocol = "icmp"
  }
# 3. สร้าง VM บน GCP
resource "google_compute_instance" "rke2_node" {
  name         = "rke2-custom-node-1"
  machine_type = "e2-medium" 
  zone         = var.gcp_zone
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50  # ✅ เพิ่มเป็น 50GB ปลอดภัยกว่า
    }
  }
  
  network_interface {
    network = "default"
    access_config {}
  }
  
  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    # Pass variables from Terraform to the Shell Script
    rancher_url          = var.rancher_url
    node_name            = "rke2-custom-node-1"
    registration_command = rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command
    node_roles           = "--etcd --controlplane --worker"
  })
  
  tags = ["allow-rke2"]  # ✅ ใช้แค่ tag เดียวที่ตรงกับ firewall
  
  
  
  depends_on = [
    rancher2_cluster_v2.student_project,
    google_compute_firewall.allow_rke2  # ✅ ใช้ underscore
  ]
}