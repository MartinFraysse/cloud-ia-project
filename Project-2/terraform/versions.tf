# versions.tf — Versions de Terraform et des providers (épinglées).
# Les contraintes sont choisies COMPATIBLES avec celles du module GKE v46 :
#   google / google-beta >= 7.28, < 9 · kubernetes >= 2.10, < 4 · random >= 2.1
# Le fichier .terraform.lock.hcl (versionné) fige ensuite la version EXACTE installée.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Ressources GCP "stables"
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0" # >= 8.0, < 9.0
    }
    # Fonctionnalités GKE en bêta, utilisées par le sous-module beta-autopilot-*
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
    # Exigé par le module (il ne crée aucun objet Kubernetes dans notre configuration)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    # Exigé par le module (tirage aléatoire des zones du cluster régional)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
