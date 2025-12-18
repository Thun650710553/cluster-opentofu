output "node_ip" {
  value = google_compute_instance.rke2_node.network_interface.0.access_config.0.nat_ip
}