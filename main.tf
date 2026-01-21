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

# 1. ✅ สร้าง Cluster V2 (RKE2)
resource "rancher2_cluster_v2" "student_project" {
  name               = "student-rke2-cluster"
  kubernetes_version = var.workload_kubernetes_version
  
  rke_config {
    machine_global_config = <<EOF
cni: "calico"
disable-kube-proxy: false
etcd-expose-metrics: true
EOF
  }
}

# 2. ✅ (สำคัญมาก) สร้าง Firewall Rule ให้ GCP ยอมรับ Traffic
resource "google_compute_firewall" "allow-rke2" {
  name    = "allow-rke2"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "6443", "9345", "10250", "2379", "2380", "30000-32767"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472", "30000-32767"] # 8472 สำคัญมากสำหรับ Calico/Canal
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-rke2"]
}

# 3. ✅ สร้าง VM บน GCP (แก้ Script ให้ง่ายขึ้น)
resource "google_compute_instance" "rke2_node" {
  name         = "rke2-custom-node-1"
  machine_type = "e2-medium" 
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 40
    }
  }

  network_interface {
    network = "default"
    access_config {} # Public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
  
  # ต้องติด Tag ให้ตรงกับ Firewall Rule
  tags = ["rancher-node","http-server", "https-server","allow-rke2"] 

  metadata_startup_script = <<-EOF
    #!/bin/bash
    exec > /var/log/rke2-install.log 2>&1
    set -x
    
    echo "[INFO] Fixing Ubuntu 22.04 iptables..."
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    update-alternatives --set arptables /usr/sbin/arptables-legacy
    update-alternatives --set ebtables /usr/sbin/ebtables-legacy
    
    echo "[INFO] Installing curl..."
    apt-get update -y && apt-get install -y curl
    
    echo "[INFO] Running Rancher registration..."
    # Let Rancher's command handle RKE2 installation
    ${rancher2_cluster_v2.student_project.cluster_registration_token[0].insecure_node_command} --etcd --controlplane --worker
    
    echo "[INFO] Registration complete!"
  EOF
  
  depends_on = [
    rancher2_cluster_v2.student_project,
    google_compute_firewall.allow-rke2
  ]
}