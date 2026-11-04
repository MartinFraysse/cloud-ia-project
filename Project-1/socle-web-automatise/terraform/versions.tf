# =============================================================================
# versions.tf — UNIQUE déclaration des versions : Terraform lui-même et les providers.
# Aucun autre bloc required_providers n'existe dans le projet (modules compris).
# Les versions exactes réellement utilisées sont figées dans .terraform.lock.hcl (versionné).
# =============================================================================
terraform {
  # >= 1.9 : les blocs "validation" de variables.tf référencent d'autres variables
  # (ex. la zone doit appartenir à la région), possibilité apparue en Terraform 1.9.
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
  }
}
