# providers.tf — Configuration des providers Google : projet et région du lab.
# Authentification : Application Default Credentials (gcloud auth application-default login).
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
