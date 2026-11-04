# =============================================================================
# modules/network/outputs.tf — sorties du module réseau, remontées à la racine.
# =============================================================================

output "network_id" {
  description = "Identifiant complet du VPC."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Nom du VPC."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "Identifiant complet du sous-réseau, à fournir au module compute."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "Nom du sous-réseau."
  value       = google_compute_subnetwork.this.name
}

output "subnet_cidr" {
  description = "Plage CIDR effective du sous-réseau."
  value       = google_compute_subnetwork.this.ip_cidr_range
}

output "firewall_rule_names" {
  description = "Noms des règles de firewall créées."
  value       = [google_compute_firewall.allow_http.name, google_compute_firewall.allow_ssh.name]
}
