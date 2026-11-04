# =============================================================================
# local/node/Dockerfile — image des nœuds locaux (node1, node2...).
# Reprise de managed-node/ des labs, avec systemd en PID 1 pour se comporter comme une VM
# Debian 12 de GCP : mêmes paquets clés (sshd, python3, sudo), mêmes services gérés par systemd.
# =============================================================================
FROM debian:bookworm-slim

# Indique à systemd qu'il tourne dans un conteneur : il saute les unités matérielles
ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus \
        openssh-server sudo python3 \
        curl iproute2 procps \
    && rm -rf /var/lib/apt/lists/*

# Comme sur GCP : un utilisateur "ansible" sudoer sans mot de passe (banc local uniquement ;
# sur GCP, c'est l'agent invité qui le crée à partir des métadonnées ssh-keys).
RUN useradd -m -s /bin/bash ansible && \
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible && \
    chmod 440 /etc/sudoers.d/ansible && \
    mkdir -p /home/ansible/.ssh && chmod 700 /home/ansible/.ssh

# Clé publique produite par local/scripts/generate-keys.sh (ignorée par Git), intégrée au build
COPY authorized_keys /home/ansible/.ssh/authorized_keys
RUN chmod 600 /home/ansible/.ssh/authorized_keys && \
    chown -R ansible:ansible /home/ansible/.ssh

# sshd est un service démarré par systemd (il n'est pas le PID 1), comme sur une VM
RUN systemctl enable ssh

# Signal d'arrêt propre attendu par systemd (sinon "docker stop" attend 10 s puis tue)
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
