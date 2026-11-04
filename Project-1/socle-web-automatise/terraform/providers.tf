# =============================================================================
# providers.tf — configuration du provider Google (versions : voir versions.tf).
# Authentification : Application Default Credentials du poste
# ("gcloud auth application-default login"), aucune clé de compte de service dans le dépôt.
# =============================================================================
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
