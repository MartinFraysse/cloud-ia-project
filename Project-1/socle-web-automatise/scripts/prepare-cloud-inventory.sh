#!/usr/bin/env bash
# =============================================================================
# scripts/prepare-cloud-inventory.sh — prépare l'accès d'Ansible au cloud, après "terraform apply".
# À lancer sur le POSTE (là où tournent terraform et gcloud), pas dans le controller.
#
#   1. Génère ansible/inventories/cloud/fleet.gcp.yml (NON versionné) à partir du modèle
#      versionné fleet.gcp.yml.example, en y injectant le project_id lu dans les outputs
#      Terraform : l'identifiant de la session de lab n'est jamais écrit dans un fichier suivi.
#   2. Copie les Application Default Credentials de gcloud dans .secrets/gcp-adc.json
#      (NON versionné, droits 600), que le controller lit via GOOGLE_APPLICATION_CREDENTIALS.
#
# Usage : ./scripts/prepare-cloud-inventory.sh [PROJECT_ID]
#   sans argument, le project_id est lu avec "terraform -chdir=terraform output -raw project_id".
# Prérequis : terraform apply effectué, "gcloud auth application-default login" effectué.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # = socle-web-automatise/
TEMPLATE="$ROOT_DIR/ansible/inventories/cloud/fleet.gcp.yml.example"
INVENTORY="$ROOT_DIR/ansible/inventories/cloud/fleet.gcp.yml"
SECRETS_DIR="$ROOT_DIR/.secrets"
# Dossier de configuration gcloud : CLOUDSDK_CONFIG s'il est défini, sinon %APPDATA%\gcloud
# sous Windows (Git Bash), sinon ~/.config/gcloud (Linux, macOS, WSL).
if [ -n "${CLOUDSDK_CONFIG:-}" ]; then
  GCLOUD_CONFIG_DIR="$CLOUDSDK_CONFIG"
elif [ -n "${APPDATA:-}" ] && [ -d "${APPDATA}/gcloud" ]; then
  GCLOUD_CONFIG_DIR="${APPDATA}/gcloud"
else
  GCLOUD_CONFIG_DIR="$HOME/.config/gcloud"
fi
ADC_SRC="${GOOGLE_APPLICATION_CREDENTIALS:-$GCLOUD_CONFIG_DIR/application_default_credentials.json}"

# --- 1. Inventaire dynamique ---------------------------------------------------------------
if [ $# -ge 1 ]; then
  PROJECT_ID="$1"
else
  PROJECT_ID="$(terraform -chdir="$ROOT_DIR/terraform" output -raw project_id 2>/dev/null || true)"
  if [ -z "$PROJECT_ID" ]; then
    echo "ERREUR : project_id introuvable dans les outputs Terraform." >&2
    echo "Lancer d'abord 'terraform -chdir=terraform apply', ou passer le projet en argument :" >&2
    echo "  ./scripts/prepare-cloud-inventory.sh <PROJECT_ID>" >&2
    exit 1
  fi
fi
# Format d'un identifiant de projet GCP : protège aussi le sed ci-dessous
if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  echo "ERREUR : project_id invalide : '$PROJECT_ID'" >&2
  exit 1
fi
sed "s/__GCP_PROJECT_ID__/$PROJECT_ID/" "$TEMPLATE" > "$INVENTORY"
echo "Inventaire généré : ansible/inventories/cloud/fleet.gcp.yml (projet $PROJECT_ID)"

# --- 2. Identifiants pour le controller ----------------------------------------------------
if [ ! -f "$ADC_SRC" ]; then
  echo "ERREUR : identifiants introuvables ($ADC_SRC)." >&2
  echo "Lancer d'abord : gcloud auth application-default login" >&2
  exit 1
fi
install -d -m 700 "$SECRETS_DIR"
install -m 600 "$ADC_SRC" "$SECRETS_DIR/gcp-adc.json"
echo "Identifiants copiés : .secrets/gcp-adc.json (lus par le controller)"

echo
echo "Suite, dans le controller (cd local && docker compose exec controller bash) :"
echo "  ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph"
echo "  ansible-playbook  -i inventories/cloud/fleet.gcp.yml site.yml"
