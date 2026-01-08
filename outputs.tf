output "node_ip" {
  value = google_compute_instance.rke2_node.network_interface.0.access_config.0.nat_ip
}

output "cluster_id" {
  description = "Rancher Cluster ID"
  value       = rancher2_cluster_v2.student_project.id
}