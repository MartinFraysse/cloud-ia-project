# =============================================================================
# modules/compute/variables.tf — entrées du module VM.
# =============================================================================

variable "instance_count" {
  description = "Nombre de VM à créer."
  type        = number
}

variable "name_prefix" {
  description = "Préfixe des noms de VM ; un suffixe -1, -2... est ajouté."
  type        = string
}

variable "zone" {
  description = "Zone des VM."
  type        = string
}

variable "machine_type" {
  description = "Type de machine Compute Engine."
  type        = string
}

variable "image" {
  description = "Image (ou famille d'images) de démarrage."
  type        = string
}

variable "disk_size_gb" {
  description = "Taille du disque de démarrage, en Go."
  type        = number
}

variable "disk_type" {
  description = "Type du disque de démarrage."
  type        = string
}

variable "subnetwork_id" {
  description = "Identifiant du sous-réseau (sortie subnet_id du module network)."
  type        = string
}

variable "network_tags" {
  description = "Tags réseau des VM (cibles des règles de firewall)."
  type        = list(string)
}

variable "labels" {
  description = "Labels des VM (au minimum env, role, team)."
  type        = map(string)

  validation {
    condition     = alltrue([for key in ["env", "role", "team"] : contains(keys(var.labels), key)])
    error_message = "Les labels doivent contenir au minimum les clés env, role et team."
  }
}

variable "ssh_user" {
  description = "Utilisateur SSH créé sur les VM à partir de la métadonnée ssh-keys."
  type        = string
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH (format OpenSSH, une ligne)."
  type        = string
}

variable "enable_os_login" {
  description = "Active OS Login sur les VM (désactivé : l'accès se fait par la métadonnée ssh-keys)."
  type        = bool
  default     = false
}
