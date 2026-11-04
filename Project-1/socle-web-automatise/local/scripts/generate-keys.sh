#!/usr/bin/env bash
# =============================================================================
# local/scripts/generate-keys.sh — génère la clé SSH de déploiement du socle (jamais committée).
#
#   local/ssh/fleet_key        clé privée : utilisée par Ansible (copiée dans le controller)
#   local/ssh/fleet_key.pub    clé publique : injectée dans les VM GCP par Terraform
#   local/node/authorized_keys copie de la clé publique, intégrée à l'image des nœuds au build
#
# À lancer sur le poste, AVANT le premier "docker compose up --build". Idempotent : une clé
# existante est conservée. Pour la renouveler : supprimer local/ssh/, relancer ce script,
# puis "docker compose up -d --build" (et "terraform apply" côté cloud).
# =============================================================================
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # = dossier local/
KEY_PATH="$LOCAL_DIR/ssh/fleet_key"

mkdir -p "$LOCAL_DIR/ssh"
if [ -f "$KEY_PATH" ]; then
  echo "Clé déjà présente : $KEY_PATH (conservée)."
else
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "fleetinfo-deploy"
fi
chmod 600 "$KEY_PATH"
cp "$KEY_PATH.pub" "$LOCAL_DIR/node/authorized_keys"
echo "Clé publique copiée dans local/node/authorized_keys (intégrée aux nœuds au prochain build)."
