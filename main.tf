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

# ✅ FIX 1: สร้าง Cluster พร้อมตั้งค่าให้ Generate Token
resource "rancher2_cluster_v2" "student_project" {
  name = "student-rke2-cluster"
  
  # ✅ ใช้ตัวแปร Kubernetes Version
  kubernetes_version = var.workload_kubernetes_version
  
  # ✅ เพิ่ม Agent Env Variables
  agent_env_vars = {
    "HTTP_PROXY"  = ""
    "HTTPS_PROXY" = ""
  }
  
  rke_config {
    machine_global_config = <<EOF
cni: "calico"
EOF
  }

  # ✅ Force Renewal ของ Token (ถ้า Token หมดอายุ)
  lifecycle {
    ignore_changes = [
      agent_env_vars
    ]
  }
}

# ✅ FIX 2: สร้าง Registration Token อย่างชัดเจน
resource "rancher2_cluster_register_token" "student_token" {
  cluster_id = rancher2_cluster_v2.student_project.id
  
  # ต้องรอให้ Cluster สร้างสำเร็จ
  depends_on = [rancher2_cluster_v2.student_project]
}

# ✅ FIX 3: สร้าง VM ด้วย Startup Script ที่ถูกต้อง
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

  # ✅ FIX 4: Startup Script ที่ Robust
  metadata_startup_script = base64decode(base64encode(<<-EOF
#!/bin/bash
# ========================================
# RKE2 Node Registration Script
# ========================================

exec > /var/log/rke2-install.log 2>&1
set -x

echo "[INFO] Starting RKE2 Installation at $(date)..."

# 1. ติดตั้ง Dependencies
apt-get update -y
apt-get install -y curl wget jq

# 2. เช็ค Token จาก Rancher
RANCHER_API="${rancher_api_url}"
TOKEN_NAME="${cluster_token_name}"
REGISTRATION_CMD="${registration_command}"

echo "[INFO] Registration Command:"
echo "$REGISTRATION_CMD"

# 3. ตรวจสอบ Command ไม่ว่าง
if [ -z "$REGISTRATION_CMD" ]; then
  echo "[ERROR] Registration command is empty!"
  echo "[ERROR] Cluster might not be ready yet."
  exit 1
fi

# 4. รันคำสั่ง Join ด้วย sudo
echo "[INFO] Executing registration command..."
eval "sudo $REGISTRATION_CMD --etcd --controlplane --worker"

if [ $? -eq 0 ]; then
  echo "[SUCCESS] Registration completed!"
else
  echo "[ERROR] Registration failed with exit code $?"
  exit 1
fi

# 5. รอให้ Service เริ่มต้น
echo "[INFO] Waiting for rancher-system-agent service..."
sleep 15

if systemctl is-active --quiet rancher-system-agent; then
  echo "[SUCCESS] rancher-system-agent is running!"
else
  echo "[WARNING] Service might still be starting..."
  journalctl -u rancher-system-agent -n 20
fi

echo "[INFO] Installation completed at $(date)"
EOF
  ))

  # ✅ เก็บตัวแปรที่ Script ต้องใช้
  metadata = merge(
    {
      ssh-keys = "ubuntu:${var.ssh_public_key}"
    },
    {
      # เพิ่มเติม Environment Variables
      "rancher-api-url"      = var.rancher_url
      "cluster-token-name"   = rancher2_cluster_register_token.student_token.name
    }
  )

  # ✅ รอให้ Token สร้างเสร็จ
  depends_on = [
    rancher2_cluster_v2.student_project,
    rancher2_cluster_register_token.student_token
  ]

  tags = ["rke2-node", "student-project"]
}