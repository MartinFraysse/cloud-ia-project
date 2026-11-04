#!/bin/sh
# =============================================================================
# local/controller/read-vault-password.sh — fournit le mot de passe Ansible Vault au controller.
#
# Désigné par ANSIBLE_VAULT_PASSWORD_FILE (local/docker-compose.yml) : Ansible exécute ce
# script et lit le mot de passe sur sa sortie standard. Pourquoi un script plutôt que le
# fichier /workspace/.vault_pass directement : sous Windows, un fichier monté depuis le poste
# apparaît exécutable (777) et Ansible tenterait alors de l'EXÉCUTER au lieu de le lire.
# Le mot de passe reste dans socle-web-automatise/.vault_pass (non versionné, cf. README).
# =============================================================================
set -eu

VAULT_PASS_FILE=/workspace/.vault_pass

if [ ! -s "$VAULT_PASS_FILE" ]; then
  echo "Mot de passe Vault introuvable : créer socle-web-automatise/.vault_pass sur le poste (cf. README, Prérequis et accès)." >&2
  exit 1
fi
# Première ligne uniquement, sans fin de ligne (fichier éventuellement édité sous Windows : CRLF)
head -n 1 "$VAULT_PASS_FILE" | tr -d '\r\n'
