output "node_ip" {
  value = google_compute_instance.rke2_node.network_interface.0.access_config.0.nat_ip
}
output "node_command" {
  description = "Command to manually join node to cluster"
  value       = rancher2_cluster_register_token.student_token.node_command
  sensitive   = true
}

output "node_command_insecure" {
  description = "Insecure node command (for testing only)"
  value       = rancher2_cluster_register_token.student_token.insecure_node_command
}

output "cluster_id" {
  description = "Rancher Cluster ID"
  value       = rancher2_cluster_v2.student_project.id
}