# =============================================================================
# modules/network/variables.tf — entrées du module réseau.
# =============================================================================

variable "network_name" {
  description = "Nom du VPC (unique dans le projet) ; préfixe des noms des règles de firewall."
  type        = string
}

variable "subnet_name" {
  description = "Nom du sous-réseau."
  type        = string
}

variable "region" {
  description = "Région du sous-réseau."
  type        = string
}

variable "subnet_cidr" {
  description = "Plage CIDR du sous-réseau."
  type        = string
}

variable "target_tag" {
  description = "Tag réseau des VM ciblées par les règles de firewall."
  type        = string
}

variable "http_port" {
  description = "Port TCP HTTP autorisé en entrée."
  type        = number
}

variable "http_source_ranges" {
  description = "Plages CIDR autorisées sur le port HTTP."
  type        = list(string)
}

variable "ssh_port" {
  description = "Port TCP SSH autorisé en entrée."
  type        = number
}

variable "ssh_source_ranges" {
  description = "Plages CIDR autorisées sur le port SSH (IP de l'opérateur)."
  type        = list(string)
  sensitive   = true
}
