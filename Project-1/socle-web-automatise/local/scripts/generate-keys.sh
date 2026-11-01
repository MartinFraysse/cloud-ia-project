#!/usr/bin/env bash
# Rôle : générer la paire de clés SSH controller -> nœuds (jamais committée).
# À lancer une fois, AVANT d'ouvrir le Dev Container. Idempotent.
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # = dossier local/
KEY_PATH="$LOCAL_DIR/ssh/fleet_key"

mkdir -p "$LOCAL_DIR/ssh"
if [ -f "$KEY_PATH" ]; then
  echo "Clé déjà présente : $KEY_PATH (rien à faire)."
else
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "fleetinfo-local"
fi
chmod 600 "$KEY_PATH"
cp "$KEY_PATH.pub" "$LOCAL_DIR/node/authorized_keys"   # intégrée à l'image au build
echo "Clé publique copiée dans local/node/authorized_keys."