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

# 1. สร้าง "ตั๋ว" รอไว้ใน Rancher (Logical Cluster)
resource "rancher2_cluster_v2" "student_project" {
  name = "student-rke2-cluster"
  
  # สำคัญ: ต้องเป็นเวอร์ชันที่มีจริงใน Rancher (เช่น v1.28.10+rke2r1)
  kubernetes_version = var.workload_kubernetes_version 
  
  # เปิดให้ Agent ปรับแต่งค่าได้
  rke_config {
    machine_global_config = <<EOF
cni: "calico"
EOF
  }
}

# 2. สร้าง VM และสั่งให้ถือตั๋ววิ่งไป Join (Physical Node)
resource "google_compute_instance" "rke2_node" {
  name         = "rke2-custom-node-1"
  machine_type = "e2-medium" # ถ้าไหวแนะนำ e2-standard-2 จะลื่นกว่า
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 40
    }
  }

  network_interface {
    network = "default"
    access_config {} # รับ Public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }

  # --- จุดแก้ที่สำคัญที่สุด (Startup Script) ---
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # บันทึก Log ทุกอย่างลงไฟล์นี้ (ถ้าพัง ให้ ssh มาเปิดไฟล์นี้ดู)
    exec > /var/log/rke2-install.log 2>&1
    set -x

    echo "[INFO] 1. Preparing Node..."
    apt-get update -y && apt-get install -y curl

    echo "[INFO] 2. Retrieving Join Command from Terraform..."
    # ดึงคำสั่ง Join ที่ Rancher สร้างให้ มาเก็บใส่ตัวแปร
    # (คำสั่งนี้จะหน้าตาประมาณ: curl ... | sudo sh -)
    CMD='${rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command}'

    # กำหนด Role ให้กับ Node นี้ (เป็นทุกอย่างในเครื่องเดียว)
    ROLES="--etcd --controlplane --worker"

    echo "[INFO] 3. Executing Join Command with Roles..."
    # สั่งรันคำสั่ง Join พร้อมพ่วง Role เข้าไป
    # (eval จำเป็นเพื่อให้ shell เข้าใจคำสั่งยาวๆ)
    eval "$CMD $ROLES"

    echo "[INFO] Installation script finished."
  EOF

  # ต้องรอให้ Cluster สร้างใน Rancher เสร็จก่อน ถึงจะสร้าง VM ได้
  depends_on = [ rancher2_cluster_v2.student_project ]
}
