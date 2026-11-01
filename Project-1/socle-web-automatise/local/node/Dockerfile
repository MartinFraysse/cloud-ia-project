# Rôle : image des nœuds locaux (node1, node2). Reprise de managed-node/ des labs,
# avec systemd en PID 1 pour se comporter comme une VM Debian 12 de GCP.
FROM debian:bookworm-slim

# Indique à systemd qu'il tourne dans un conteneur : il saute les unités matérielles
ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus \
        openssh-server sudo python3 \
        curl iproute2 procps \
    && rm -rf /var/lib/apt/lists/*

# Identique au lab : utilisateur ansible + sudo sans mot de passe (banc local uniquement)
RUN useradd -m -s /bin/bash ansible && \
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible && \
    chmod 440 /etc/sudoers.d/ansible && \
    mkdir -p /home/ansible/.ssh && chmod 700 /home/ansible/.ssh

# Identique au lab : clé publique produite par generate-keys.sh (ignorée par Git)
COPY authorized_keys /home/ansible/.ssh/authorized_keys
RUN chmod 600 /home/ansible/.ssh/authorized_keys && \
    chown -R ansible:ansible /home/ansible/.ssh

# Nouveau : sshd est un service démarré par systemd, il n'est plus le PID 1
RUN systemctl enable ssh

# Signal d'arrêt propre attendu par systemd (sinon "docker stop" attend 10 s puis tue)
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]