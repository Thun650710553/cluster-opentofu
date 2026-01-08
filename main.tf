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

# ✅ สร้าง Cluster V2 (RKE2)
resource "rancher2_cluster_v2" "student_project" {
  name               = "student-rke2-cluster"
  kubernetes_version = var.workload_kubernetes_version
  
  rke_config {
    machine_global_config = <<EOF
cni: "calico"
EOF
  }
}

# ✅ ดึง Registration Token จาก Cluster
# (Rancher v2/RKE2 สร้าง Token อัตโนมัติ)
data "rancher2_cluster_v2" "student_cluster" {
  name = rancher2_cluster_v2.student_project.name
  
  depends_on = [rancher2_cluster_v2.student_project]
}

# ✅ สร้าง VM บน GCP
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

  # ✅ Startup Script - ดึง Token จาก Rancher API
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

# 2. ตั้งค่า Variables
RANCHER_URL="${var.rancher_url}"
RANCHER_TOKEN="${var.rancher_access_key}"
CLUSTER_ID="${rancher2_cluster_v2.student_project.id}"

echo "[INFO] Rancher URL: $RANCHER_URL"
echo "[INFO] Cluster ID: $CLUSTER_ID"

# 3. ดึง Registration Token จาก Rancher API
echo "[INFO] Fetching registration token from Rancher API..."
RESPONSE=$(curl -s -k \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  "$RANCHER_URL/v1/clusters/$CLUSTER_ID/clusterregistrationtoken")

echo "[DEBUG] API Response:"
echo "$RESPONSE" | jq .

# 4. ดึง Command จาก Response
REGISTRATION_CMD=$(echo "$RESPONSE" | jq -r '.items[0].insecureNodeCommand // .items[0].nodeCommand // empty' 2>/dev/null)

echo "[INFO] Registration Command:"
echo "$REGISTRATION_CMD"

# 5. ตรวจสอบ Command ไม่ว่าง
if [ -z "$REGISTRATION_CMD" ] || [ "$REGISTRATION_CMD" == "null" ]; then
  echo "[ERROR] Registration command is empty!"
  echo "[ERROR] Cluster might not be ready yet or API call failed."
  echo "[DEBUG] Full response: $RESPONSE"
  sleep 30
  # ลองอีกครั้ง
  RESPONSE=$(curl -s -k \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    "$RANCHER_URL/v1/clusters/$CLUSTER_ID/clusterregistrationtoken")
  REGISTRATION_CMD=$(echo "$RESPONSE" | jq -r '.items[0].insecureNodeCommand // empty')
  
  if [ -z "$REGISTRATION_CMD" ]; then
    echo "[FATAL] Still cannot get registration command. Exiting."
    exit 1
  fi
fi

# 6. รันคำสั่ง Join ด้วย Roles
echo "[INFO] Executing registration command with roles..."
eval "sudo $REGISTRATION_CMD --etcd --controlplane --worker"

if [ $? -eq 0 ]; then
  echo "[SUCCESS] Registration completed!"
else
  echo "[ERROR] Registration failed with exit code $?"
  exit 1
fi

# 7. รอให้ Service เริ่มต้น
echo "[INFO] Waiting for rancher-system-agent service..."
sleep 20

if systemctl is-active --quiet rancher-system-agent; then
  echo "[SUCCESS] rancher-system-agent is running!"
  systemctl status rancher-system-agent
else
  echo "[WARNING] Service might still be starting..."
  journalctl -u rancher-system-agent -n 50
fi

echo "[INFO] Installation completed at $(date)"
EOF
  ))

  depends_on = [
    rancher2_cluster_v2.student_project
  ]

  tags = ["rke2-node", "student-project"]
}
