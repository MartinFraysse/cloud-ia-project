# variables.tf — TOUTES les variables de la configuration (et uniquement ici).
# project_id et region n'ont PAS de valeur par défaut : ils changent à chaque session de lab
# et sont fournis par terraform.tfvars (non versionné).

variable "project_id" {
  type        = string
  description = "ID du projet GCP fourni par le lab (panneau du lab ou `gcloud config get-value project`). Ex. : qwiklabs-gcp-01-0123456789ab."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id doit être un ID de projet GCP valide (6 à 30 caractères : minuscules, chiffres, tirets)."
  }
}

variable "region" {
  type        = string
  description = "Région GCP du cluster, fournie par le lab. Autopilot = cluster régional. Ex. : us-central1, europe-west1."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region doit être une région GCP (ex. us-central1), pas une zone (ex. us-central1-a)."
  }
}

variable "cluster_name" {
  type        = string
  description = "Nom du cluster GKE. Imposé par l'énoncé : autopilot-cluster-1."
  default     = "autopilot-cluster-1"
}

variable "network" {
  type        = string
  description = "Nom du réseau VPC où créer le cluster. Le projet de lab fournit le réseau \"default\"."
  default     = "default"
}

variable "subnetwork" {
  type        = string
  description = "Nom du sous-réseau (dans la région du cluster). \"default\" = sous-réseau automatique de la région."
  default     = "default"
}

variable "ip_range_pods" {
  type        = string
  description = "Nom de la plage IP secondaire pour les pods. null = plage gérée automatiquement par GKE."
  default     = null
}

variable "ip_range_services" {
  type        = string
  description = "Nom de la plage IP secondaire pour les Services. null = plage gérée automatiquement par GKE."
  default     = null
}

variable "release_channel" {
  type        = string
  description = "Canal de mise à jour automatique de GKE : RAPID, REGULAR (équilibre nouveauté / stabilité) ou STABLE."
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel doit valoir RAPID, REGULAR ou STABLE."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Protection contre la suppression du cluster. false pour pouvoir faire terraform destroy en fin de lab."
  default     = false
}
