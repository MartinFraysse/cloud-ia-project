# Rôle : poste de contrôle Ansible (Ansible ne tourne pas nativement sous Windows).
# Reprise du Dev Container des labs.
FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client git curl vim less \
    && rm -rf /var/lib/apt/lists/*

# Versions bornées : ansible 10 = ansible-core 2.17.
# google-auth + requests : dépendances Python du plugin d'inventaire google.cloud.gcp_compute (étape cloud)
RUN pip install --no-cache-dir \
        "ansible>=10,<11" \
        "ansible-lint>=24,<25" \
        google-auth requests

WORKDIR /workspace