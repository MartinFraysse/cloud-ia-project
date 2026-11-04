#!/bin/sh
# =============================================================================
# local/controller/entrypoint.sh — préparation du controller à chaque démarrage.
#
# 1. Recopie la clé privée de déploiement dans /root/.ssh avec les droits 600 : ssh refuse une
#    clé lisible par d'autres, or un dossier monté depuis Windows apparaît en 777 et chmod n'y a
#    aucun effet. La clé reste générée sur le poste (local/scripts/generate-keys.sh) et n'est
#    jamais intégrée à l'image ni versionnée.
# 2. Installe les dépendances Galaxy (requirements.yml, versions épinglées) si elles sont
#    absentes du projet, pour que le controller soit immédiatement utilisable. Sans accès
#    Internet, un simple avertissement : "ansible-galaxy install -r requirements.yml" à relancer.
# =============================================================================
set -eu

KEY_SRC=/workspace/local/ssh/fleet_key
KEY_DST=/root/.ssh/fleet_key
ANSIBLE_DIR=/workspace/ansible

install -d -m 700 /root/.ssh
if [ -f "$KEY_SRC" ]; then
  install -m 600 "$KEY_SRC" "$KEY_DST"
else
  echo "ATTENTION : $KEY_SRC introuvable. Lancer local/scripts/generate-keys.sh sur le poste," >&2
  echo "puis 'docker compose up -d --build' (les nœuds intègrent la clé publique au build)." >&2
fi

if [ ! -d "$ANSIBLE_DIR/collections/ansible_collections/google/cloud" ] \
   || [ ! -d "$ANSIBLE_DIR/roles/geerlingguy.nginx" ]; then
  echo "Installation des dépendances Galaxy (requirements.yml)..."
  (cd "$ANSIBLE_DIR" && ansible-galaxy install -r requirements.yml) \
    || echo "ATTENTION : installation Galaxy impossible ; relancer 'ansible-galaxy install -r requirements.yml'." >&2
fi

exec "$@"
