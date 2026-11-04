# =============================================================================
# locals.tf — valeurs calculées à partir des variables, transmises aux modules par main.tf.
# =============================================================================
locals {
  # Labels posés sur chaque VM. L'inventaire dynamique Ansible les exploite :
  #   app  -> filtre de sélection des VM  (labels.app = fleetinfo)
  #   role -> groupe Ansible "web"        (keyed_groups, même nom qu'en local)
  #   env  -> groupe Ansible "env_cloud"
  vm_labels = {
    app  = var.app_name
    env  = var.environment
    role = var.server_role
    team = var.team
  }

  # Contenu de la clé publique (sans retour à la ligne final, pour une métadonnée stable)
  ssh_public_key = trimspace(file(var.ssh_public_key_path))

  # Pour les outputs : suffixe ":<port>" des URL (vide sur le port 80) et chemin de la clé
  # privée exprimé depuis la racine du socle (ssh_public_key_path est relatif à terraform/).
  http_port_suffix     = var.http_port == 80 ? "" : ":${var.http_port}"
  ssh_private_key_path = trimprefix(trimsuffix(var.ssh_public_key_path, ".pub"), "../")
}
