# =============================================================================
# main.tf — racine du socle : instancie les modules et relie leurs entrées/sorties.
# Aucune ressource n'est déclarée ici : réseau et VM vivent dans modules/.
#
#   module.network  -> VPC dédié + sous-réseau + règles de firewall (HTTP, SSH restreint)
#   module.compute  -> N VM Debian 12 branchées sur le sous-réseau de module.network
# =============================================================================

module "network" {
  source = "./modules/network"

  network_name       = "${var.name_prefix}-vpc"
  subnet_name        = "${var.name_prefix}-subnet-${var.region}"
  region             = var.region
  subnet_cidr        = var.subnet_cidr
  target_tag         = var.network_tag
  http_port          = var.http_port
  http_source_ranges = var.http_source_ranges
  ssh_port           = var.ssh_port
  ssh_source_ranges  = var.ssh_source_ranges
}

module "compute" {
  source = "./modules/compute"

  instance_count = var.vm_count
  name_prefix    = "${var.name_prefix}-${var.server_role}"
  zone           = var.zone
  machine_type   = var.machine_type
  image          = var.vm_image
  disk_size_gb   = var.boot_disk_size_gb
  disk_type      = var.boot_disk_type
  subnetwork_id  = module.network.subnet_id # sortie du module réseau -> entrée du module VM
  network_tags   = [var.network_tag]
  labels         = local.vm_labels
  ssh_user       = var.ssh_user
  ssh_public_key = local.ssh_public_key
}
