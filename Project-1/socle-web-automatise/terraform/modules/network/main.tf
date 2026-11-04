# =============================================================================
# modules/network/main.tf — réseau du socle : VPC dédié, sous-réseau, règles de firewall.
#
# Module autonome : il ne connaît que ses variables d'entrée et expose ses outputs ; il ne
# référence aucune ressource d'un autre module. Les règles de firewall ciblent les VM par
# TAG RÉSEAU (var.target_tag), jamais « toutes les instances » du réseau.
# =============================================================================

# VPC dédié en mode "custom" : pas de sous-réseau créé automatiquement dans chaque région
# (contrairement au réseau "default"), on déclare uniquement celui dont le socle a besoin.
resource "google_compute_network" "this" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.subnet_cidr
}

# HTTP : la page Fleet Info et /health sont consultables depuis var.http_source_ranges.
resource "google_compute_firewall" "allow_http" {
  name        = "${var.network_name}-allow-http"
  network     = google_compute_network.this.id
  description = "HTTP vers les VM portant le tag ${var.target_tag} (Fleet Info, /health, /status)."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.http_port)]
  }

  source_ranges = var.http_source_ranges
  target_tags   = [var.target_tag]
}

# SSH : réservé aux plages de l'opérateur (son IP publique en /32), seul point d'entrée
# d'Ansible. Fermé au reste d'Internet pour éviter le scan et la force brute sur le port 22.
resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.network_name}-allow-ssh"
  network     = google_compute_network.this.id
  description = "SSH vers les VM portant le tag ${var.target_tag}, depuis les seules plages de l'opérateur."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.ssh_port)]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = [var.target_tag]
}
