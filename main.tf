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
    apt-get update -y && apt-get install -y curl
    ${rancher2_cluster_v2.student_project.cluster_registration_token.0.insecure_node_command} --etcd --controlplane --worker
  EOF

  depends_on = [ rancher2_cluster_v2.student_project ]
}