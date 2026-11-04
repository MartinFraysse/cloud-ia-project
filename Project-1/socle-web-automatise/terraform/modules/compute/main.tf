# =============================================================================
# modules/compute/main.tf — VM Compute Engine du socle, en nombre paramétrable.
#
# Module autonome : il reçoit l'identifiant du sous-réseau en entrée (var.subnetwork_id),
# sans connaître le module qui l'a créé. Terraform crée les VM ; il n'y installe rien
# (pas de startup-script) : toute la configuration est faite ensuite par Ansible.
# =============================================================================

resource "google_compute_instance" "this" {
  # count : passer de 2 à 3 VM = changer var.instance_count. En réduisant le nombre,
  # Terraform supprime les VM de plus fort indice (fleetinfo-web-3, puis -2...).
  count = var.instance_count

  name         = format("%s-%d", var.name_prefix, count.index + 1)
  machine_type = var.machine_type
  zone         = var.zone

  # Tag réseau : cible des règles de firewall. Labels : sélection et groupes de
  # l'inventaire dynamique Ansible (google.cloud.gcp_compute).
  tags   = var.network_tags
  labels = var.labels

  boot_disk {
    auto_delete = true # le disque disparaît avec la VM : rien ne survit à terraform destroy

    initialize_params {
      image = var.image
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id

    # Bloc vide = IP publique éphémère : nécessaire pour qu'Ansible (depuis le poste) et
    # les navigateurs atteignent la VM sans bastion ni load balancer.
    access_config {}
  }

  metadata = {
    # Clé publique de déploiement : l'agent invité GCE crée l'utilisateur var.ssh_user,
    # sudoer sans mot de passe. Aucune clé privée ne transite par Terraform.
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
    # Désactive OS Login sur ces VM pour que la métadonnée ssh-keys soit prise en compte,
    # même si le projet du lab active OS Login par défaut (choix justifié dans docs/decisions.md).
    enable-oslogin = var.enable_os_login ? "TRUE" : "FALSE"
  }

  # Autorise Terraform à arrêter la VM pour appliquer un changement de machine_type.
  allow_stopping_for_update = true
}
