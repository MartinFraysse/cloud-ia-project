# =============================================================================
# variables.tf — variables d'entrée GLOBALES du socle (racine).
# Valeurs concrètes : terraform.tfvars (non versionné), copié depuis terraform.tfvars.example.
# Règle : pas de "default" pour ce qui change d'une session de lab à l'autre (projet, région,
# zone, nombre de VM, IP de l'opérateur) ; un "default" uniquement pour les vraies options.
# Tableau récapitulatif : README.md, section Terraform.
# =============================================================================

# --- Session de lab (obligatoires, sans valeur par défaut) ----------------------------------

variable "project_id" {
  description = "Identifiant du projet GCP de la session de lab (panneau du lab, ou : gcloud config get-value project)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id doit être un identifiant de projet GCP valide (6 à 30 caractères : minuscules, chiffres, tirets)."
  }
}

variable "region" {
  description = "Région GCP du sous-réseau (imposée ou autorisée par le lab, ex. us-central1)."
  type        = string
}

variable "zone" {
  description = "Zone GCP des VM ; doit appartenir à la région (ex. us-central1-f pour us-central1)."
  type        = string

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "La zone doit appartenir à la région choisie (ex. region = \"us-central1\" -> zone = \"us-central1-f\")."
  }
}

variable "vm_count" {
  description = "Nombre de VM web (2 à 10). Passer de 2 à 3 ne demande que de changer cette valeur."
  type        = number

  validation {
    condition     = var.vm_count >= 2 && var.vm_count <= 10 && floor(var.vm_count) == var.vm_count
    error_message = "vm_count doit être un entier entre 2 et 10 (le socle exige au moins 2 VM)."
  }
}

variable "ssh_source_ranges" {
  description = "Plages CIDR IPv4 autorisées en SSH (22) : l'IP publique du poste de l'opérateur en /32 (préfixe /16 minimum, jamais 0.0.0.0/0)."
  type        = list(string)
  # Donnée personnelle (IP publique de l'opérateur) : masquée dans la sortie de plan/apply
  # et dans les journaux CI. La valeur reste lisible dans terraform.tfvars et dans le state.
  sensitive = true

  # Plages IPv4 uniquement (les VM n'ont qu'une IP publique IPv4 : une règle IPv6 ne laisserait
  # jamais passer le SSH d'Ansible) et étroites : préfixe /16 au minimum. Interdit donc
  # 0.0.0.0/0 et ses contournements (0.0.0.0/1 + 128.0.0.0/1, 203.0.113.10/0...).
  validation {
    condition = length(var.ssh_source_ranges) > 0 && alltrue([
      for cidr in var.ssh_source_ranges :
      can(cidrnetmask(cidr)) && can(tonumber(split("/", cidr)[1])) && try(tonumber(split("/", cidr)[1]) >= 16, false)
    ])
    error_message = "ssh_source_ranges : plages IPv4 au format CIDR, préfixe /16 minimum (ex. [\"203.0.113.10/32\"]). Jamais 0.0.0.0/0. IP publique IPv4 du poste : curl -4 -s https://ifconfig.me"
  }
}

# --- Options (valeur par défaut adaptée au lab) ----------------------------------------------

variable "name_prefix" {
  description = "Préfixe des noms de ressources (VPC, sous-réseau, firewall, VM)."
  type        = string
  default     = "fleetinfo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "name_prefix : 2 à 21 caractères, minuscules, chiffres et tirets, commençant par une lettre."
  }
}

variable "subnet_cidr" {
  description = "Plage CIDR du sous-réseau des VM."
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr doit être une plage CIDR IPv4 valide (ex. 10.10.0.0/24)."
  }
}

variable "http_port" {
  description = "Port HTTP ouvert sur les VM (doit correspondre à socle_http_port côté Ansible)."
  type        = number
  default     = 80
}

variable "ssh_port" {
  description = "Port SSH ouvert sur les VM aux seules plages ssh_source_ranges."
  type        = number
  default     = 22
}

variable "http_source_ranges" {
  description = "Plages CIDR autorisées en HTTP. La page Fleet Info est consultable depuis Internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "network_tag" {
  description = "Tag réseau commun des VM web : seule cible des règles de firewall."
  type        = string
  default     = "fleetinfo-web"
}

variable "machine_type" {
  description = "Type de machine Compute Engine des VM (vérifier ceux autorisés par le lab)."
  type        = string
  default     = "e2-small"
}

variable "vm_image" {
  description = "Image de démarrage des VM (famille Debian 12 maintenue par Google)."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "boot_disk_size_gb" {
  description = "Taille du disque de démarrage des VM, en Go."
  type        = number
  default     = 10
}

variable "boot_disk_type" {
  description = "Type du disque de démarrage (pd-standard, pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "ssh_user" {
  description = "Utilisateur créé sur les VM par l'agent invité GCE (métadonnée ssh-keys) ; c'est l'ansible_user du cloud."
  type        = string
  default     = "ansible"
}

variable "ssh_public_key_path" {
  description = "Chemin de la clé publique SSH injectée dans les VM (générée par local/scripts/generate-keys.sh)."
  type        = string
  default     = "../local/ssh/fleet_key.pub"

  validation {
    condition     = fileexists(var.ssh_public_key_path)
    error_message = "Clé publique introuvable : lancer local/scripts/generate-keys.sh, ou corriger ssh_public_key_path."
  }
}

# --- Labels (identification des VM, utilisés par l'inventaire dynamique Ansible) -------------

variable "environment" {
  description = "Valeur du label env des VM (l'inventaire Ansible en dérive le groupe env_<valeur>)."
  type        = string
  default     = "cloud"
}

variable "server_role" {
  description = "Valeur du label role des VM : l'inventaire Ansible en dérive le groupe du même nom, ciblé par site.yml (web)."
  type        = string
  default     = "web"
}

variable "team" {
  description = "Valeur du label team des VM (équipe propriétaire)."
  type        = string
  default     = "plateforme"
}

variable "app_name" {
  description = "Valeur du label app des VM : filtre de sélection de l'inventaire dynamique (labels.app = fleetinfo)."
  type        = string
  default     = "fleetinfo"
}
