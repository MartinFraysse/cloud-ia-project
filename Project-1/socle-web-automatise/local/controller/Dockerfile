# =============================================================================
# local/controller/Dockerfile — poste de contrôle Ansible du socle (local ET cloud).
# Ansible ne s'exécute pas nativement sous Windows : ce conteneur garantit à toute l'équipe
# (Windows, macOS, Linux) les mêmes versions d'Ansible et de ses dépendances.
# Reprise du Dev Container des labs.
# =============================================================================
FROM python:3.12-slim

# Client SSH (connexion aux nœuds et aux VM), git et quelques outils de diagnostic
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client git curl vim less \
    && rm -rf /var/lib/apt/lists/*

# Versions Python ÉPINGLÉES (cf. requirements.txt) : ansible-core, ansible-lint et les
# bibliothèques du plugin d'inventaire google.cloud.gcp_compute.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Prépare la clé SSH (droits 600) et les dépendances Galaxy à chaque démarrage, puis lance
# la commande demandée. fleet-vault-pass lit le mot de passe Vault dans /workspace/.vault_pass
# (voir read-vault-password.sh : contourne les droits 777 des montages Windows).
COPY entrypoint.sh /usr/local/bin/controller-entrypoint
COPY read-vault-password.sh /usr/local/bin/fleet-vault-pass
RUN chmod 755 /usr/local/bin/controller-entrypoint /usr/local/bin/fleet-vault-pass
ENTRYPOINT ["/usr/local/bin/controller-entrypoint"]

WORKDIR /workspace/ansible
# Garde le conteneur vivant : on y entre avec "docker compose exec controller bash"
CMD ["sleep", "infinity"]
