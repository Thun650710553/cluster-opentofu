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

# 1. สร้าง Cluster ใน Rancher (V2/RKE2)
resource "rancher2_cluster_v2" "student_project" {
  name = "student-rke2-cluster"
  
  # แก้ไขจุดที่ 1: ใช้ตัวแปรรับเวอร์ชัน Kubernetes (ต้องมีค่าจริง เช่น "v1.28.10+rke2r1")
  kubernetes_version = var.workload_kubernetes_version
  
  rke_config {
    # เพิ่ม Config พื้นฐาน (Optional แต่ใส่ไว้ก็ดีครับ)
    machine_global_config = <<EOF
cni: "calico"
EOF
  }
}

# 2. สร้าง VM บน GCP และสั่งให้ Join Cluster อัตโนมัติ
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
    access_config {} # ขอ Public IP
  }

  metadata = {
    # แก้ไขจุดที่ 2: รับ SSH Key จากตัวแปร (Clean Code)
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }

  # แก้ไขจุดที่ 3: Startup Script แบบ Robust (บันทึก Log + ใส่ Role ครบ)
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # 1. บันทึก Log ทุกอย่างลงไฟล์ /var/log/rke2-install.log (เอาไว้ Debug)
    exec > /var/log/rke2-install.log 2>&1
    set -x

    echo "[INFO] Starting RKE2 Installation..."

    # 2. ติดตั้งเครื่องมือจำเป็น
    apt-get update -y && apt-get install -y curl

    # 3. ดึงคำสั่ง Join จาก Terraform มาเก็บใส่ตัวแปร CMD
    # (คำสั่งนี้คือ curl ... | sudo sh -)
    CMD='${rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command}'
    
    # 4. กำหนด Role ให้กับ Node นี้ (เป็นทุกอย่าง: Database, Controlplane, Worker)
    ROLES="--etcd --controlplane --worker"

    echo "[INFO] Executing Join Command..."
    
    # 5. รันคำสั่ง Join (ใช้ eval เพื่อให้รวม CMD และ ROLES เข้าด้วยกันถูกต้อง)
    eval "$CMD $ROLES"

    echo "[INFO] Installation script finished."
    
    # เช็คสถานะ Service (รอ 20 วิ)
    sleep 20
    systemctl status rancher-system-agent
  EOF

  # บังคับให้รอ Cluster สร้างใน Rancher เสร็จก่อน
  depends_on = [ rancher2_cluster_v2.student_project ]
}