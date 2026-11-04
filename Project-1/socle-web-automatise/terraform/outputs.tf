# =============================================================================
# outputs.tf — sorties utiles à l'exploitation (terraform output), sans console GCP.
# Aucune ne porte de donnée sensible (les IP de l'opérateur, sensibles, ne sont pas exposées).
# =============================================================================

# --- Réseau ---

output "network_name" {
  description = "Nom du VPC dédié au socle."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Nom du sous-réseau des VM."
  value       = module.network.subnet_name
}

output "subnet_cidr" {
  description = "Plage CIDR du sous-réseau des VM."
  value       = module.network.subnet_cidr
}

output "firewall_rules" {
  description = "Règles de firewall créées (HTTP ouvert, SSH restreint)."
  value       = module.network.firewall_rule_names
}

output "network_tag" {
  description = "Tag réseau commun des VM, cible des règles de firewall."
  value       = var.network_tag
}

# --- VM ---

output "vm_names" {
  description = "Noms des VM web (noms d'hôte Ansible dans l'inventaire dynamique)."
  value       = module.compute.instance_names
}

output "vm_public_ips" {
  description = "IP publique de chaque VM, par nom de VM."
  value       = module.compute.public_ips
}

output "vm_internal_ips" {
  description = "IP interne de chaque VM, par nom de VM."
  value       = module.compute.internal_ips
}

output "fleetinfo_urls" {
  description = "URL de la page d'accueil Fleet Info de chaque VM."
  value       = { for name, ip in module.compute.public_ips : name => "http://${ip}${local.http_port_suffix}/" }
}

output "health_urls" {
  description = "URL du contrôle de santé /health de chaque VM."
  value       = { for name, ip in module.compute.public_ips : name => "http://${ip}${local.http_port_suffix}/health" }
}

output "ssh_commands" {
  description = "Commande SSH de chaque VM, à lancer depuis la racine du socle (socle-web-automatise/)."
  value       = { for name, ip in module.compute.public_ips : name => "ssh -i ${local.ssh_private_key_path} ${var.ssh_user}@${ip}" }
}

# --- Paramètres de la session, réutilisés par scripts/prepare-cloud-inventory.sh ---

output "project_id" {
  description = "Projet GCP de la session (injecté dans l'inventaire dynamique Ansible généré)."
  value       = var.project_id
}

output "zone" {
  description = "Zone des VM."
  value       = var.zone
}
