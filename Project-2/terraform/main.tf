# main.tf — Création du cluster GKE Autopilot avec le module officiel imposé.
# Terraform crée UNIQUEMENT le cluster : l'application est déployée par Helm.
module "gke" {
  # Sous-module Autopilot à cluster public du module officiel Google (pas de google_container_cluster
  # écrit à la main). source et version sont les seules valeurs littérales autorisées par Terraform.
  source = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster"
  # Épinglage : toute version 46.x, jamais 47 (évite un changement cassant à l'insu de l'équipe).
  version = "~> 46.0"

  # Projet GCP du lab : change à chaque session → sans valeur par défaut.
  project_id = var.project_id
  # Nom du cluster (autopilot-cluster-1), repris dans les outputs et la commande de connexion.
  name = var.cluster_name
  # Autopilot est toujours RÉGIONAL : plan de contrôle et nœuds répartis sur plusieurs zones.
  region = var.region
  # Réseau VPC "default" fourni avec le projet de lab.
  network = var.network
  # Sous-réseau "default" de la région.
  subnetwork = var.subnetwork
  # null = GKE crée et gère lui-même la plage IP des pods.
  ip_range_pods = var.ip_range_pods
  # null = GKE utilise sa plage par défaut pour les Services.
  ip_range_services = var.ip_range_services
  # Canal de mises à jour automatiques du plan de contrôle et des nœuds.
  release_channel = var.release_channel
  # false : sinon terraform destroy échoue en fin de lab.
  deletion_protection = var.deletion_protection
}
