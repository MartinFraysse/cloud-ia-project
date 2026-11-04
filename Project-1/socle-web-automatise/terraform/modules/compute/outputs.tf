# =============================================================================
# modules/compute/outputs.tf — sorties du module VM, remontées à la racine.
# =============================================================================

output "instance_names" {
  description = "Noms des VM, dans l'ordre de création."
  value       = google_compute_instance.this[*].name
}

output "public_ips" {
  description = "IP publiques des VM, par nom de VM."
  value       = { for vm in google_compute_instance.this : vm.name => vm.network_interface[0].access_config[0].nat_ip }
}

output "internal_ips" {
  description = "IP internes des VM, par nom de VM."
  value       = { for vm in google_compute_instance.this : vm.name => vm.network_interface[0].network_ip }
}

output "self_links" {
  description = "Liens complets (self_link) des VM."
  value       = google_compute_instance.this[*].self_link
}
