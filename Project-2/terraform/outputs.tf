# outputs.tf — Informations utiles à l'exploitation, lues dans les OUTPUTS DU MODULE
# (et non recopiées des valeurs d'entrée) : elles reflètent ce qui a réellement été créé.

output "cluster_name" {
  description = "Nom du cluster GKE créé."
  value       = module.gke.name
}

output "cluster_location" {
  description = "Location réelle du cluster (région, car Autopilot est régional)."
  value       = module.gke.location
}

output "project_id" {
  description = "Projet GCP du cluster, extrait de l'ID du cluster (projects/<projet>/locations/<loc>/clusters/<nom>)."
  value       = split("/", module.gke.cluster_id)[1]
}

output "cluster_endpoint" {
  description = "Adresse IP de l'API Kubernetes (plan de contrôle). Sensible : terraform output -raw cluster_endpoint."
  value       = module.gke.endpoint
  sensitive   = true
}

output "kubernetes_version" {
  description = "Version Kubernetes actuelle du plan de contrôle."
  value       = module.gke.master_version
}

output "release_channel" {
  description = "Canal de mise à jour effectivement appliqué au cluster."
  value       = module.gke.release_channel
}

output "get_credentials_command" {
  description = "Commande à copier pour configurer kubectl sur ce cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${split("/", module.gke.cluster_id)[1]}"
}
