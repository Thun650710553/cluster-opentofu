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

resource "rancher2_cluster_v2" "student_project" {
  name = "student-rke2-cluster"
  kubernetes_version = var.workload_kubernetes_version
  rke_config {}
}

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
    access_config {}
  }

  metadata = {
   # ssh-keys = "ubuntu:${file("id_rsa.pub")}"
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    # 1. ตั้งค่า Log เพื่อให้ Debug ง่าย (สำคัญมากตอนมีปัญหา)
    exec > /var/log/rke2-install.log 2>&1
    set -x

    echo "[INFO] Starting Installation..."

    # 2. ติดตั้ง Prerequisite
    apt-get update -y && apt-get install -y curl

    # 3. เตรียม Role flags (Node นี้เป็น All-in-one ต้องเหมาหมด)
    # เราไม่เขียนลง config.yaml แต่เราส่งผ่าน Command Line เพื่อให้ System Agent รับรู้
    ROLES="--etcd --controlplane --worker"

    # 4. ดึงคำสั่งจาก Terraform มาเก็บใส่ตัวแปร
    # (เราใช้ insecure_node_command เพราะมันคือ script ที่ถูกต้องจาก Rancher)
    RANCHER_CMD='${rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command}'
    
    echo "[INFO] Joining Rancher with command: $RANCHER_CMD $ROLES"

    # 5. รันคำสั่ง Join (สำคัญ: ต้องเติม Roles ต่อท้าย)
    eval "$RANCHER_CMD $ROLES"

    echo "[INFO] Installation script finished. Checking service..."
    # รอสักพักแล้วเช็คว่า service ขึ้นไหม (Rancher Agent จะไปเรียก RKE2 ขึ้นมาเอง)
    sleep 20
    systemctl status rancher-system-agent || echo "[WARN] Agent might be starting..."
  EOF

# /*
#  <<-EOF
#   #!/bin/bash
#   apt-get update -y && apt-get install -y curl
#    ${rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command} --etcd --controlplane --worker
# EOF
# */

  depends_on = [ rancher2_cluster_v2.student_project ]
}