# Architecture du socle web automatisé

Ce document détaille l'architecture résumée dans le [README, section 2](../README.md#2-architecture) :
les deux environnements (local et cloud), les flux réseau, la chaîne de l'inventaire dynamique,
le cycle de vie d'un déploiement de Fleet Info et le partage des responsabilités entre les outils.

Les noms de ressources indiqués sont ceux obtenus avec les **valeurs par défaut** des variables
(`name_prefix = "fleetinfo"`, `server_role = "web"`, `network_tag = "fleetinfo-web"`...) et une
session de lab en `us-central1` / `us-central1-f`. Le `project_id` et les adresses IP sont des
exemples (`qwiklabs-gcp-00-0123456789ab`, plage documentaire `203.0.113.0/24`).

> L'environnement local est vérifié (2026-11-03). L'environnement cloud est décrit d'après le code
> et des tests hors ligne (plan Terraform, plugin d'inventaire sur une réponse simulée de l'API) :
> il reste à valider sur un vrai projet GCP lors de la répétition générale.

## Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Environnement local](#2-environnement-local)
3. [Environnement cloud](#3-environnement-cloud)
4. [Flux réseau](#4-flux-réseau)
5. [Chaîne de l'inventaire dynamique](#5-chaîne-de-linventaire-dynamique)
6. [Déroulé de site.yml](#6-déroulé-de-siteyml)
7. [Cycle de vie d'un déploiement](#7-cycle-de-vie-dun-déploiement)
8. [Retour arrière manuel](#8-retour-arrière-manuel)
9. [Frontière Terraform / Ansible](#9-frontière-terraform--ansible)
10. [Ce que possède chaque outil](#10-ce-que-possède-chaque-outil)

---

## 1. Vue d'ensemble

Principe directeur : **Terraform crée l'infrastructure, Ansible la configure et y déploie
l'application.** Le code Ansible (`site.yml`, rôles, templates) est **le même** dans les deux
environnements ; seuls l'inventaire et ses `group_vars` changent (ADR-01).

```text
                  ┌────────────────────────────────────────────────────┐
                  │ Dépôt Git : Project-1/socle-web-automatise/        │
                  │ terraform/  ansible/  local/  scripts/  docs/      │
                  └─────────┬──────────────────────────────┬───────────┘
                            │                              │
     ENVIRONNEMENT CLOUD    │                              │    ENVIRONNEMENT LOCAL
  ┌─────────────────────────v────────────┐   ┌─────────────v────────────────────────┐
  │ Terraform (poste) :                  │   │ docker compose (poste) :             │
  │   VPC + sous-réseau                  │   │   controller (ansible-core 2.17)     │
  │   2 règles de firewall (tag réseau)  │   │   node1 (Debian 12, systemd, sshd)   │
  │   N VM Debian 12 (labels, ssh-keys)  │   │   node2 (Debian 12, systemd, sshd)   │
  │                                      │   │                                      │
  │ Ansible (controller) :               │   │ Ansible (controller) :               │
  │   inventaire dynamique               │   │   inventaire statique                │
  │   google.cloud.gcp_compute           │   │   inventories/local/hosts.yml        │
  │   -> groupe « web »                  │   │   -> groupe « web »                  │
  └──────────────────┬───────────────────┘   └───────────────────┬──────────────────┘
                     │                                           │
                     └────────── MÊME site.yml ──────────────────┘
                                 MÊMES rôles common / webserver / fleetinfo
                                 MÊMES templates
                       seuls l'inventaire et inventories/<env>/group_vars/ diffèrent
```

Le **controller Ansible est le même conteneur** pour les deux environnements (ADR-02) : il tourne
sur le poste de l'opérateur, dans le projet Docker Compose du banc local, et atteint soit les
conteneurs `node1` / `node2` (réseau Docker `labnet`), soit les VM GCP (Internet, SSH sur leur IP
publique). Terraform et `gcloud`, eux, tournent directement sur le poste. Le controller déclare
`depends_on: service_healthy` sur `node1` et `node2` : `docker compose up` démarre donc aussi les
nœuds locaux quand on ne travaille que sur le cloud (sans effet sur les VM).

Ce qui diffère entre les deux environnements, et uniquement là :

| Clé | `inventories/local/group_vars/all.yml` | `inventories/cloud/group_vars/all.yml` |
|---|---|---|
| `ansible_user` | `ansible` (créé dans l'image des nœuds) | `ansible` (créé par l'agent invité GCE depuis `ssh-keys`) |
| `ansible_ssh_private_key_file` | `/root/.ssh/fleet_key` | `/root/.ssh/fleet_key` (même clé) |
| Vérification de la clé d'hôte | `ansible_host_key_checking: false` | `ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"` |
| `socle_env` | `local` | `cloud` |
| `fleetinfo_cloud_zone`, `fleetinfo_cloud_machine_type`, `fleetinfo_cloud_public_ip` | non définies (défauts du rôle : `""`) | `{{ gce_zone }}`, `{{ gce_machineType }}`, `{{ ansible_host }}` |

---

## 2. Environnement local

Fichier de référence : [`local/docker-compose.yml`](../local/docker-compose.yml) (projet Compose
`fleetinfo-local`).

```text
 Poste de l'opérateur - Docker Desktop ou Docker Engine - projet Compose « fleetinfo-local »
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                      │
│  socle-web-automatise/ (clone du dépôt) ──── bind mount « ..:/workspace:cached » ─┐  │
│                                                                                   │  │
│  ┌────────────────────────────────────────────────────────────────────────────────v┐ │
│  │ controller            image fleetinfo-local/controller:ansible-core-2.17        │ │
│  │   base python:3.12-slim, ansible-core 2.17.14, ansible-lint 25.9.2,             │ │
│  │   google-auth, requests (local/controller/requirements.txt)                     │ │
│  │   working_dir /workspace/ansible, init: true, aucun port publié                 │ │
│  │   ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg                                 │ │
│  │   GOOGLE_APPLICATION_CREDENTIALS=/workspace/.secrets/gcp-adc.json (cloud)       │ │
│  │   entrypoint : local/ssh/fleet_key -> /root/.ssh/fleet_key (mode 600)           │ │
│  │   depends_on : node1 et node2 « service_healthy »                               │ │
│  └───────────────────┬──────────────────────────────────────┬──────────────────────┘ │
│                      │ SSH 22, utilisateur ansible,         │                        │
│                      │ clé /root/.ssh/fleet_key             │                        │
│ ═════════════════════╪═══ réseau bridge « labnet » ═════════╪═══════════════════════ │
│                      │    (DNS Docker : node1, node2)       │                        │
│  ┌───────────────────v───────────────┐  ┌───────────────────v───────────────┐        │
│  │ node1           (hostname node1)  │  │ node2           (hostname node2)  │        │
│  │ image fleetinfo-local/            │  │ image fleetinfo-local/            │        │
│  │       node:debian12               │  │       node:debian12               │        │
│  │ debian:bookworm-slim              │  │ debian:bookworm-slim              │        │
│  │ PID 1 = systemd -> ssh, nginx     │  │ PID 1 = systemd -> ssh, nginx     │        │
│  │ utilisateur ansible, sudo         │  │ utilisateur ansible, sudo         │        │
│  │   NOPASSWD, authorized_keys       │  │   NOPASSWD, authorized_keys       │        │
│  │   intégré au build                │  │   intégré au build                │        │
│  │ privileged, cgroup: host,         │  │ privileged, cgroup: host,         │        │
│  │ volume /sys/fs/cgroup (rw),       │  │ volume /sys/fs/cgroup (rw),       │        │
│  │ tmpfs /run et /run/lock           │  │ tmpfs /run et /run/lock           │        │
│  │ healthcheck :                     │  │ healthcheck :                     │        │
│  │   systemctl is-active ssh         │  │   systemctl is-active ssh         │        │
│  │ nginx :80 (après site.yml)        │  │ nginx :80 (après site.yml)        │        │
│  └───────────────────┬───────────────┘  └───────────────────┬───────────────┘        │
│                      │ port publié 8081:80                  │ port publié 8082:80    │
└──────────────────────┼──────────────────────────────────────┼────────────────────────┘
                       v                                      v
             http://localhost:8081                  http://localhost:8082
             (navigateur ou curl du poste)          (navigateur ou curl du poste)
```

Points clés :

| Élément | Détail | Pourquoi |
|---|---|---|
| Nœuds « comme des VM » | `debian:bookworm-slim` + `systemd` en PID 1 (`CMD ["/lib/systemd/systemd"]`, `STOPSIGNAL SIGRTMIN+3`), `sshd` lancé par systemd (`systemctl enable ssh`) ; paquets `openssh-server`, `sudo`, `python3`, `dbus`, `curl`, `iproute2`, `procps` | Ansible les gère exactement comme les VM GCP : connexion SSH, modules `service` / `timezone` (D-Bus), handlers (ADR-03). |
| `privileged`, `cgroup: host`, `/sys/fs/cgroup:rw`, tmpfs `/run` et `/run/lock` | Exigences de systemd dans un conteneur | Banc local uniquement, jamais en production. |
| Ancre YAML `x-node` | Définition commune des nœuds (build, image, privilèges, volumes, healthcheck, réseau) | Ajouter un nœud = quelques lignes (bloc `node3` commenté dans `docker-compose.yml`, plus `hosts.yml` et `depends_on`). |
| Image unique | `fleetinfo-local/node:debian12`, construite une fois, partagée par les nœuds | Build rapide, nœuds identiques. |
| Healthcheck | `systemctl is-active --quiet ssh` toutes les 5 s, 12 essais | Le controller (`depends_on: service_healthy`) et `docker compose up --wait` attendent que SSH soit prêt. |
| Clé SSH | Générée sur le poste par `local/scripts/generate-keys.sh` ; la clé publique est copiée dans `local/node/authorized_keys` puis intégrée à l'image au build ; la clé privée est recopiée en `600` par l'entrypoint du controller | Rien de secret dans les images ni dans Git ; contourne le montage en `777` sous Windows. |
| Résolution des noms | `node1` / `node2` résolus par le DNS du réseau `labnet` | Aucune IP dans `inventories/local/hosts.yml`. |
| Vérification de clé d'hôte | Désactivée (`ansible_host_key_checking: false`) | Les clés d'hôte sont générées par l'installation d'`openssh-server` pendant le build : elles sont donc communes à tous les nœuds et changent dès que cette couche de l'image est reconstruite ; réseau Docker privé. |
| Ports publiés | `8081:80` (node1), `8082:80` (node2) | Consultation des pages depuis le navigateur du poste. Sans adresse d'écoute précisée, Docker publie ces ports sur toutes les interfaces du poste. |
| Pas d'IPv6 | Le site nginx n'a pas de `listen [::]` | Les conteneurs n'ont pas d'IPv6 : nginx refuserait de démarrer. |

Ce que le controller voit dans `/workspace` (montage du dossier `socle-web-automatise/` du poste) :

| Chemin dans le controller | Contenu | Utilisé par |
|---|---|---|
| `/workspace/ansible` | Code Ansible (répertoire de travail) ; `roles/geerlingguy.nginx/` et `collections/`, installés automatiquement par l'entrypoint au démarrage s'ils manquent | `ansible-playbook`, `ansible-galaxy`, `ansible-lint` |
| `/workspace/.vault_pass` | Mot de passe du coffre (non versionné) | Lu par le script `/usr/local/bin/fleet-vault-pass` (`ANSIBLE_VAULT_PASSWORD_FILE`), insensible aux droits `777` des montages Windows ; hors controller : `vault_password_file = ../.vault_pass` (`ansible.cfg`) |
| `/workspace/local/ssh/fleet_key` | Clé privée de déploiement (non versionnée) | Copiée en `/root/.ssh/fleet_key` par l'entrypoint au démarrage du conteneur |
| `/workspace/.secrets/gcp-adc.json` | ADC copiées par `prepare-cloud-inventory.sh` (cloud uniquement) | Plugin `google.cloud.gcp_compute` via `GOOGLE_APPLICATION_CREDENTIALS` |
| `/workspace/ansible/inventories/cloud/fleet.gcp.yml` | Inventaire dynamique généré (cloud uniquement) | `-i inventories/cloud/fleet.gcp.yml` |

Le montage étant en lecture-écriture, ce que le controller installe dans `ansible/` (rôle et
collections Galaxy) persiste sur le poste entre deux démarrages. Sous Linux, ces fichiers
appartiennent à `root` sur le poste (le controller tourne en root) : voir
[RB-07](runbooks.md#rb-07-détruire-lenvironnement-proprement) pour leur suppression.

---

## 3. Environnement cloud

Fichiers de référence : [`terraform/main.tf`](../terraform/main.tf),
[`terraform/modules/network/main.tf`](../terraform/modules/network/main.tf),
[`terraform/modules/compute/main.tf`](../terraform/modules/compute/main.tf).

```text
 Google Cloud - projet temporaire du lab (ex. qwiklabs-gcp-00-0123456789ab)
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ VPC « fleetinfo-vpc »  (google_compute_network, auto_create_subnetworks = false)     │
│                                                                                      │
│  Règles de firewall INGRESS, cible = tag réseau « fleetinfo-web » uniquement :       │
│    fleetinfo-vpc-allow-http   tcp:80   source http_source_ranges = ["0.0.0.0/0"]     │
│    fleetinfo-vpc-allow-ssh    tcp:22   source ssh_source_ranges  = ["<IP poste>/32"] │
│                                        (variable sensible : « (sensitive value) »)   │
│  Règles implicites du VPC : entrée refusée par défaut, sortie autorisée (apt).       │
│                                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Sous-réseau « fleetinfo-subnet-us-central1 »  10.10.0.0/24  région us-central1 │  │
│  │                                                                                │  │
│  │  Zone us-central1-f                                                            │  │
│  │  ┌──────────────────────────────┐ ┌──────────────────────────────┐             │  │
│  │  │ fleetinfo-web-1              │ │ fleetinfo-web-2              │   ...       │  │
│  │  │ e2-small, debian-cloud/      │ │ (identique, index 2)         │ fleetinfo-  │  │
│  │  │   debian-12                  │ │                              │ web-N       │  │
│  │  │ disque 10 Go pd-balanced,    │ │                              │ (N =        │  │
│  │  │   auto_delete                │ │                              │ vm_count)   │  │
│  │  │ IP interne 10.10.0.x         │ │                              │             │  │
│  │  │ IP publique éphémère (natIP) │ │                              │             │  │
│  │  │ tags   : fleetinfo-web       │ │                              │             │  │
│  │  │ labels : app=fleetinfo       │ │                              │             │  │
│  │  │          env=cloud           │ │                              │             │  │
│  │  │          role=web            │ │                              │             │  │
│  │  │          team=plateforme     │ │                              │             │  │
│  │  │ metadata :                   │ │                              │             │  │
│  │  │   ssh-keys = ansible:<clé    │ │                              │             │  │
│  │  │     publique fleet_key.pub>  │ │                              │             │  │
│  │  │   enable-oslogin = FALSE     │ │                              │             │  │
│  │  └──────────────────────────────┘ └──────────────────────────────┘             │  │
│  └────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Rôle de chaque attribut posé par Terraform :

| Attribut | Valeur (défauts) | Consommé par |
|---|---|---|
| Tag réseau | `fleetinfo-web` (`var.network_tag`) | Les deux règles de firewall (`target_tags`) : aucune règle ne vise « toutes les instances ». |
| Label `app` | `fleetinfo` (`var.app_name`) | Filtre de l'inventaire dynamique : `labels.app = fleetinfo`. |
| Label `role` | `web` (`var.server_role`) | `keyed_groups` de l'inventaire : groupe Ansible `web`, ciblé par `site.yml`. |
| Label `env` | `cloud` (`var.environment`) | `keyed_groups` : groupe Ansible `env_cloud`. |
| Label `team` | `plateforme` (`var.team`) | Identification du propriétaire (exigence des consignes ; validée par le module `compute`). |
| Métadonnée `ssh-keys` | `ansible:<contenu de ../local/ssh/fleet_key.pub>` | Agent invité GCE : crée l'utilisateur `ansible`, sudoer sans mot de passe (ADR-06). |
| Métadonnée `enable-oslogin` | `FALSE` (`enable_os_login = false`, défaut du module) | Garantit la prise en compte de `ssh-keys` même si le projet du lab active OS Login. |
| `access_config {}` | IP publique éphémère | `ansible_host` (via `natIP`) et accès navigateur, sans bastion ni load balancer. Elle change si la VM est recréée ou arrêtée puis redémarrée. |
| `allow_stopping_for_update` | `true` | Permet à Terraform de changer `machine_type` (arrêt puis redémarrage de la VM, donc nouvelle IP publique). |
| `boot_disk.auto_delete` | `true` | Le disque disparaît avec la VM : rien ne survit à `terraform destroy`. |

Terraform **n'installe rien** sur les VM (pas de `startup-script`, pas de compte de service
attaché) : une VM fraîchement créée est une Debian 12 nue, entièrement configurée ensuite par
Ansible.

Dimensionnement : `vm_count` pilote le `count` du module `compute`. Les VM sont nommées
`<name_prefix>-<server_role>-<index>` à partir de 1 ; réduire `vm_count` supprime les VM de plus
fort indice.

---

## 4. Flux réseau

```text
   Poste de l'opérateur (IP publique 203.0.113.10)                     Google Cloud
  ┌─────────────────────────────────────────────┐
  │ terraform ─────────── HTTPS 443 ────────────┼──(1)──> API Compute Engine
  │ gcloud ────────────── HTTPS 443 ────────────┼──(1)──> API OAuth / Compute
  │                                             │
  │ ┌─ Docker ────────────────────────────────┐ │
  │ │ controller ──────── HTTPS 443 ──────────┼─┼──(2)──> API Compute Engine (inventaire)
  │ │ controller ──────── SSH 22 ─────────────┼─┼──(3)──> natIP des VM  [allow-ssh, /32]
  │ │ controller ──(4) SSH 22 ──> node1, node2│ │
  │ │ node1:80 <──(5)── localhost:8081        │ │
  │ │ node2:80 <──(5)── localhost:8082        │ │
  │ └─────────────────────────────────────────┘ │
  │ navigateur / curl ─── HTTP 80 ──────────────┼──(6)──> natIP des VM  [allow-http]
  │ ssh (poste) ───────── SSH 22 ───────────────┼──(3)──> natIP des VM  [allow-ssh, /32]
  └─────────────────────────────────────────────┘
                                         Sur chaque serveur (local ou cloud) :
                                         module uri ──(7)──> http://127.0.0.1:80/health
                                         apt ──(8)──> dépôts Debian (sortie Internet)
```

| # | Source | Destination | Port | Autorisé par | Usage |
|---|---|---|---|---|---|
| 1 | `terraform`, `gcloud` (poste) | API Google Cloud | 443/tcp | Terraform : ADC de l'utilisateur (`gcloud auth application-default login`). `gcloud` : ses propres identifiants (`gcloud auth login`). | Terraform : création et destruction de l'infrastructure. `gcloud` : authentification, diagnostic (`gcloud compute instances list`...). |
| 2 | Controller (conteneur sur le poste) | API Google (jeton OAuth, Compute Engine) | 443/tcp | ADC copiées dans `.secrets/gcp-adc.json` | Inventaire dynamique `google.cloud.gcp_compute` (lecture seule). |
| 3 | Controller, ou client `ssh` du poste | IP publique des VM | 22/tcp | Règle `fleetinfo-vpc-allow-ssh` : source = IP publique du poste en `/32`. Le trafic du conteneur sort par la NAT de Docker puis par l'accès Internet du poste : c'est bien l'IP publique du poste que voit GCP. | Connexion Ansible (`ansible` + clé `fleet_key`), SSH d'exploitation. |
| 4 | Controller | `node1`, `node2` | 22/tcp | Réseau Docker `labnet` | Connexion Ansible en local. |
| 5 | Poste (`localhost:8081`, `localhost:8082`) | `node1:80`, `node2:80` | 80/tcp | Ports publiés par Compose | Page Fleet Info, `/health`, `/status` en local. |
| 6 | Navigateur, `curl` | IP publique des VM | 80/tcp | Règle `fleetinfo-vpc-allow-http` (`0.0.0.0/0`) | Page Fleet Info, `/health`, `/status` sur le cloud. |
| 7 | Le serveur lui-même | `127.0.0.1:80` | 80/tcp | Boucle locale | Contrôle de santé après bascule : le module `uri` s'exécute **sur** le serveur, à travers nginx. |
| 8 | Les serveurs | Dépôts Debian | 80/443 | Sortie autorisée par défaut (VPC) / NAT Docker | Installation des paquets (`nginx`, `python3-passlib`...). |

Conséquence opérationnelle : **si l'IP publique du poste change** (changement de réseau, box
redémarrée), le flux 3 est bloqué (timeout SSH). Mettre à jour `ssh_source_ranges` dans
`terraform/terraform.tfvars` puis relancer `terraform apply`.

Endpoints HTTP servis par nginx (template
[`roles/webserver/templates/fleetinfo.conf.j2`](../ansible/roles/webserver/templates/fleetinfo.conf.j2)) :

| Chemin | Contenu | Protection |
|---|---|---|
| `/` | `index.html` de la release active (racine `/opt/fleetinfo/current`) | Aucune. |
| `/health` | `health.json` de la release active (`default_type application/json`) ; `404` si la release n'en contient pas | Aucune. |
| `/status` | `stub_status` de nginx (journal d'accès désactivé) | Authentification HTTP Basic (`/etc/nginx/fleetinfo-status.htpasswd`, compte `exploitation`), et filtrage IP optionnel (`webserver_status_allowed_networks`). |

Le site écoute en `default_server` sur `webserver_listen_port` (= `socle_http_port`, 80), avec
les en-têtes `X-Content-Type-Options: nosniff` et `X-Frame-Options: DENY` ; la version de nginx
est masquée (`nginx_server_tokens: "off"`).

---

## 5. Chaîne de l'inventaire dynamique

Fichiers de référence :
[`inventories/cloud/fleet.gcp.yml.example`](../ansible/inventories/cloud/fleet.gcp.yml.example),
[`scripts/prepare-cloud-inventory.sh`](../scripts/prepare-cloud-inventory.sh),
[`inventories/cloud/group_vars/all.yml`](../ansible/inventories/cloud/group_vars/all.yml).
Décision : ADR-07.

```text
 terraform/terraform.tfvars (non versionné)     project_id, region, zone, vm_count...
            │
            v  terraform apply                  (poste)
 VM étiquetées app=fleetinfo, env=cloud, role=web, team=plateforme
            │
            v  terraform output -raw project_id
 scripts/prepare-cloud-inventory.sh             (poste, après apply)
   ├─> ansible/inventories/cloud/fleet.gcp.yml   (non versionné)
   │     = fleet.gcp.yml.example avec __GCP_PROJECT_ID__ remplacé par le project_id
   │       (format du project_id contrôlé avant remplacement)
   └─> .secrets/gcp-adc.json                     (non versionné, mode 600)
         = copie de ~/.config/gcloud/application_default_credentials.json
           (ou du fichier désigné par GOOGLE_APPLICATION_CREDENTIALS / CLOUDSDK_CONFIG)
            │
            v  montage /workspace + GOOGLE_APPLICATION_CREDENTIALS
 controller : ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
            │
            v  plugin google.cloud.gcp_compute 1.15.0 (auth_kind: application),
            │  choisi par le mécanisme « auto » grâce au suffixe .gcp.yml
 API Compute Engine : instances du projet, toutes zones
   filtre envoyé à l'API : (labels.app = fleetinfo) (status = RUNNING)
            │
            v  pour chaque VM retenue
   hostnames : name                 -> hôte « fleetinfo-web-1 »
   vars_prefix : gce_               -> gce_zone, gce_machineType, gce_labels...
   compose : ansible_host           -> networkInterfaces[0].accessConfigs[0].natIP
             ansible_user           -> metadata['ssh-keys'].split(':')[0]  (« ansible »)
   keyed_groups : labels.role       -> groupe « web »        (prefix "", separator "")
                  labels.env        -> groupe « env_cloud »
                  zone              -> groupe « zone_us_central1_f »
            │
            v  + inventories/cloud/group_vars/all.yml
   ansible_user: ansible (repli), ansible_ssh_private_key_file: /root/.ssh/fleet_key,
   ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new", socle_env: cloud,
   fleetinfo_cloud_zone: "{{ gce_zone }}",
   fleetinfo_cloud_machine_type: "{{ gce_machineType }}",
   fleetinfo_cloud_public_ip: "{{ ansible_host }}"
            │
            v
 site.yml (hosts: web) : exactement le même code qu'en local
```

Remarques :

- Ce comportement a été vérifié avec le vrai plugin `google.cloud` 1.15.0 sur une réponse
  **simulée** de l'API : `--graph` donne `@web`, `@env_cloud`, `@zone_us_central1_f`, et le
  filtre envoyé est `(labels.app = fleetinfo) (status = RUNNING)`.
- `gce_zone` et `gce_machineType` contiennent le **nom court** (`us-central1-f`, `e2-small`) : le
  plugin tronque les URL complètes renvoyées par l'API.
- Le `project_id` n'est **jamais** dans un fichier versionné : l'option `projects` du plugin n'a
  pas d'équivalent en variable d'environnement, d'où la génération du fichier depuis un modèle.
- Passer de 2 à 3 VM : `vm_count = 3` puis `terraform apply`. La nouvelle VM porte les mêmes
  labels ; elle apparaît dans le groupe `web` au prochain appel du plugin, **sans modifier une
  seule ligne d'Ansible** (ni régénérer `fleet.gcp.yml`, qui ne contient que le `project_id`).
- Une VM arrêtée (`status != RUNNING`) disparaît de l'inventaire.
- L'inventaire est interrogé à chaque commande Ansible : il n'y a pas de cache, une IP publique
  qui change est prise en compte immédiatement.

Contrat d'interface entre Terraform et Ansible (à garder cohérent si l'on change une valeur) :

| Côté Terraform | Côté Ansible | Conséquence d'une incohérence |
|---|---|---|
| `app_name = "fleetinfo"` (label `app`) | `filters: labels.app = fleetinfo` (valeur écrite dans `fleet.gcp.yml.example`) | Inventaire vide. |
| `server_role = "web"` (label `role`) | `hosts: web` dans `site.yml` et `rollback.yml` | Aucun hôte ciblé (`skipping: no hosts matched`). |
| `ssh_user = "ansible"` | `ansible_user` déduit de la métadonnée `ssh-keys` par `compose` (repli : `ansible_user: ansible` de `inventories/cloud/group_vars/all.yml`) | Aucune : le `compose` suit automatiquement `ssh_user`. |
| `ssh_public_key_path = "../local/ssh/fleet_key.pub"` | `ansible_ssh_private_key_file: /root/.ssh/fleet_key` | `Permission denied (publickey)`. |
| `http_port = 80` (firewall) | `socle_http_port: 80` (`group_vars/all/vars.yml`) | Site injoignable depuis Internet. |

---

## 6. Déroulé de site.yml

[`ansible/site.yml`](../ansible/site.yml) contient trois plays courts, un par couche (ADR-09) ;
toute la logique est dans les rôles. Les facts sont collectés une fois par hôte et par exécution
(`gathering = smart`).

```text
 ansible-playbook [-i inventories/cloud/fleet.gcp.yml] site.yml
   │
   ├─ Play 1 « Appliquer le socle système commun »          hosts: web, become, tag common
   │    rôle common : vérifier Debian 12 + systemd, paquets de base, fuseau horaire,
   │                  utilisateur fleetops, /etc/motd (template motd.j2)
   │    aucun handler
   │
   ├─ Play 2 « Configurer le serveur web nginx »            hosts: web, become, tag webserver
   │    dépendance geerlingguy.nginx 3.3.1 : paquet nginx, nginx.conf validé, service,
   │                  suppression du site « default » de Debian
   │    rôle webserver : python3-passlib, htpasswd /status (no_log),
   │                     /etc/nginx/sites-enabled/fleetinfo.conf (template)
   │    fin du play -> handlers, seulement si fleetinfo.conf a changé :
   │      « Valider la configuration nginx » (nginx -t)
   │          └─ succès -> « Recharger nginx » (state: reloaded)
   │          └─ échec  -> chaîne arrêtée, nginx garde sa configuration en mémoire
   │
   └─ Play 3 « Déployer l'application Fleet Info »          hosts: web, become, tag fleetinfo
        serial: [1, "100%"], max_fail_percentage: 0 (déploiement canari, section 7.3)
        rôle fleetinfo : contrôles, arborescence, block/rescue/always, ménage
        aucun handler (la bascule du lien current ne demande pas de rechargement)
```

Pourquoi un play par couche : les handlers d'un play s'exécutent à la fin **de ce play**. La
configuration nginx est donc validée et rechargée **avant** le déploiement applicatif, qui
interroge `/health` à travers nginx.

Reload et non restart (ADR-10) : un reload relit la configuration sans couper les connexions en
cours. Le seul redémarrage du socle est celui de `geerlingguy.nginx` au premier passage.

Chaîne du secret `/status` :

```text
 group_vars/all/vault.yml (chiffré AES256, versionné)
     vault_webserver_status_password  ── déchiffré avec .vault_pass (non versionné, lu par fleet-vault-pass)
            │
            v
 group_vars/all/vars.yml :
     webserver_status_password: "{{ vault_webserver_status_password }}"
            │
            v
 rôle webserver, tâche « Créer le compte d'accès à la page /status »
   community.general.htpasswd (apr_md5_crypt, no_log: true)
            │
            v
 /etc/nginx/fleetinfo-status.htpasswd   root:www-data 0640   (empreinte seulement)
            │
            v
 location = /status { auth_basic ...; auth_basic_user_file ...; }   -> 401 sans identifiants
```

---

## 7. Cycle de vie d'un déploiement

Fichiers de référence : [`roles/fleetinfo/tasks/main.yml`](../ansible/roles/fleetinfo/tasks/main.yml),
[`prepare.yml`](../ansible/roles/fleetinfo/tasks/prepare.yml),
[`deploy.yml`](../ansible/roles/fleetinfo/tasks/deploy.yml),
[`cleanup.yml`](../ansible/roles/fleetinfo/tasks/cleanup.yml). Décision : ADR-08.

### 7.1 Arborescence sur un serveur

Exemple : état d'un serveur après le déploiement réussi de `1.1.0` (depuis `1.0.0`), puis l'échec
simulé de `1.2.0`.

```text
 /opt/fleetinfo/                               fleetinfo_base_dir (socle_app_root)
 ├── current -> /opt/fleetinfo/releases/1.1.0  lien symbolique = racine servie par nginx
 └── releases/
     ├── 1.0.0/   index.html  health.json      release précédente
     ├── 1.1.0/   index.html  health.json      release active
     └── 1.2.0/   index.html                   release en échec (sans health.json) : current y a
                                               pointé pendant le contrôle de santé, puis est
                                               revenu sur 1.1.0

 /etc/ansible/facts.d/fleetinfo.fact            fait local -> ansible_local.fleetinfo
     { "version": "1.1.0", "previous_version": "1.0.0",
       "release_dir": "/opt/fleetinfo/releases/1.1.0",
       "deployed_at": "<date du déploiement de 1.1.0>" }
     (non réécrit par l'échec de 1.2.0 : la tâche qui l'écrit vient après le contrôle /health)

 /var/log/fleetinfo/                            root:adm 0750
 └── deploy.log                                 une ligne par tentative (root:adm, 0640)
```

nginx résout le lien `current` à chaque requête (pas d'`open_file_cache`) : la bascule d'une
release à l'autre est **instantanée et ne demande aucun rechargement**. Le lien est remplacé de
façon atomique par le module `ansible.builtin.file` (`state: link`) : nginx sert soit l'ancienne
release, soit la nouvelle, jamais un mélange des deux.

### 7.2 Déroulé pour un hôte

```text
 CONTRÔLES ET ARBORESCENCE (main.yml, prepare.yml)
   argument_specs (meta/argument_specs.yml)               types des variables validés
   « Vérifier le format de la version demandée »            X.Y.Z
   « Créer les répertoires de l'application »               /opt/fleetinfo, releases/, facts.d/
   « Créer le répertoire du journal de déploiement »        /var/log/fleetinfo (root:adm 0750)

 AVANT LE BLOCK (deploy.yml)
   « Lire la release actuellement active »                 stat de /opt/fleetinfo/current
   « Mémoriser la release active avant bascule ... »        fleetinfo_active_dir (= N-1)
   « Calculer le contexte du déploiement »                  fleetinfo_deploy_needed
   « Dater le déploiement et identifier la release précédente »
   « Refuser une version imposée par -e pendant un retour arrière manuel »
   « Refuser une simulation d'échec sur la version déjà active »

 BLOCK « Déployer avec retour arrière automatique la version X »
   1. « Créer le répertoire de la release X »               releases/X/
   2. « Générer la page d'accueil de la release »           index.html  (facts + variables)
   3. « Générer la réponse du contrôle de santé ... »       health.json (sauté si simulate_failure)
   4. « Démonstration : livrer une release incomplète ... » (seulement si simulate_failure)
   5. « Basculer le lien current vers la release X »        current -> releases/X
   6. « Interroger /health jusqu'à obtenir la version X »   uri : 1 essai + 5 nouvelles
                                                            tentatives espacées de 2 s
   7. « Contrôler le statut et la version renvoyés par /health »   status == ok, version == X
   8. « Mémoriser la release active dans les facts locaux » fleetinfo.fact
   9. « Marquer le déploiement comme réussi »               statut SUCCES
            │
            │ une tâche échoue (ex. /health en 404)
            v
 RESCUE
   « Mémoriser la cause de l'échec »                     statut PROVISOIRE ECHEC_ROLLBACK_KO
                                                         (ECHEC_SANS_ROLLBACK si aucune N-1)
   « Rebasculer current vers la release précédente N-1 » si une N-1 existe
   « Recharger le service web »                          nginx reloaded (immédiat, pas de handler)
   « Confirmer le retour arrière par le contrôle de santé » (bloc imbriqué block + rescue)
       « Vérifier que /health répond de nouveau avec la version N-1 »
       « Mémoriser le succès du retour arrière »         ECHEC_ROLLBACK_OK
       rescue : « Mémoriser l'échec de la vérification du retour arrière »
                                                         ECHEC_ROLLBACK_KO conservé (+ détail)
   « Faire échouer explicitement le déploiement »        TOUJOURS atteint ; message selon le statut :
                                                         N-1 restaurée (OK), INTERVENTION MANUELLE
                                                         (KO), ou aucune version précédente

 ALWAYS
   « Tracer la tentative de déploiement dans le journal » /var/log/fleetinfo/deploy.log
     (uniquement s'il y a eu une tentative réelle : un passage sur un serveur conforme
      n'écrit rien, ce qui garantit changed=0)

 APRÈS LE BLOCK (cleanup.yml, si l'hôte n'a pas échoué)
   « Lister les releases présentes sur le serveur »
   « Supprimer les releases les plus anciennes au-delà de la limite de 3 »
     (fleetinfo_keep_releases ; la release active et la précédente sont toujours protégées)
```

Les étapes 6 et 7 utilisent `fleetinfo_health_url` = `http://127.0.0.1:80/health`
(`fleetinfo_health_host`, `fleetinfo_health_port` = `socle_http_port`, `fleetinfo_health_path`).
Le contrôle échoue si `/health` ne répond pas `200`, si la réponse n'est pas du JSON, ou si
`status` n'est pas `ok` ou `version` n'est pas la version demandée.

En mode `--check`, le contrôle `/health` est sauté (rien n'a réellement basculé) et la bascule du
lien est seulement annoncée (`force: "{{ ansible_check_mode }}"`).

Lignes réelles du journal (banc local, 2026-11-03) :

```text
2026-11-03T18:09:57Z hote=node1 type=deploiement demandee=1.1.0 precedente=1.0.0 resultat=SUCCES
2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
```

| Champ | Valeurs possibles |
|---|---|
| Date | UTC, format `AAAA-MM-JJTHH:MM:SSZ`, heure d'écriture de la ligne |
| `hote` | Nom d'hôte Ansible (`node1`, `fleetinfo-web-1`...) |
| `type` | `deploiement` (nouvelle release), `mise-a-jour-sur-place` (même version déjà active, contenu régénéré, ex. après un changement de variable affichée), `rollback-manuel` (`rollback.yml`) |
| `demandee` / `precedente` | Version demandée ; version active avant l'opération (`aucune` au premier déploiement) |
| `resultat` | `SUCCES`, `ECHEC_ROLLBACK_OK` (N-1 restaurée et vérifiée), `ECHEC_ROLLBACK_KO` (retour arrière tenté mais N-1 ne répond pas), `ECHEC_SANS_ROLLBACK` (aucune N-1 : premier déploiement ou mise à jour sur place) |
| `detail` | Tâche en échec et message d'erreur, sur une ligne (présent uniquement en cas d'échec) |

### 7.3 Déploiement canari sur plusieurs serveurs

```text
 Play « Déployer l'application Fleet Info »  serial: [1, "100%"]  max_fail_percentage: 0

 Lot 1 : premier hôte de l'inventaire, seul
         (node1 en local ; sur le cloud, en principe fleetinfo-web-1, l'ordre
          dépendant de la réponse de l'API)
     │
     ├── succès ──> Lot 2 : tous les autres hôtes en parallèle
     │
     └── échec (rescue : N-1 restaurée sur le canari, hôte en échec)
              └──> max_fail_percentage: 0 arrête le playbook : les autres hôtes ne
                   reçoivent jamais la version défectueuse et restent en N-1.
```

Résultat observé en local lors de l'échec simulé `1.2.0` : `node1` `failed=1 rescued=1`, `node2`
jamais touché par le play 3, site en ligne en `1.1.0` sur les deux nœuds. Un déploiement sain de
`1.2.0` a ensuite fonctionné normalement.

Limite inhérente à ce modèle (bascule puis contrôle) : pendant le contrôle de santé, soit une
dizaine de secondes au plus avec les valeurs par défaut, le canari sert la nouvelle release ; sans
load balancer, aucun serveur n'est retiré du trafic pendant ce temps.

### 7.4 Idempotence de la page

La page affiche la date du **dernier déploiement**, pas l'heure courante (ADR-13) :

- lors d'une bascule (`fleetinfo_deploy_needed` vrai), `fleetinfo_deployed_at` prend l'heure de
  collecte des facts (`ansible_facts.date_time.iso8601`) et est mémorisée dans
  `/etc/ansible/facts.d/fleetinfo.fact` ;
- lors d'un passage sans bascule, elle est relue depuis `ansible_local.fleetinfo.deployed_at`
  (même logique pour la version précédente affichée) ;
- le template `index.html.j2` n'affiche aucune valeur instable (heure, charge, uptime, espace
  libre) : le deuxième passage de `site.yml` donne `changed=0` ;
- la ligne de journal n'est écrite que s'il y a eu une tentative réelle (fichier généré, lien
  basculé ou échec).

### 7.5 Ménage des releases

Après un déploiement réussi, `cleanup.yml` trie les répertoires de `releases/` par date de
modification et supprime les plus anciens au-delà de `fleetinfo_keep_releases` (3), sans jamais
toucher la release active ni la précédente. Vérifié en local : au déploiement d'une 4e release
(`1.3.0`), `1.0.0` a été supprimée.

---

## 8. Retour arrière manuel

[`ansible/rollback.yml`](../ansible/rollback.yml) appelle
[`roles/fleetinfo/tasks/rollback.yml`](../ansible/roles/fleetinfo/tasks/rollback.yml), qui réutilise
`deploy.yml` **sans régénérer** la release (mêmes garde-fous, même journal).

```text
 ansible-playbook rollback.yml [-e fleetinfo_rollback_version=1.0.0]
                              [-i inventories/cloud/fleet.gcp.yml]
   │   (même canari : serial [1, "100%"], max_fail_percentage: 0)
   v
 argument_specs, point d'entrée « rollback »
 « Déterminer la version cible du retour arrière »
     fleetinfo_rollback_version si fourni, sinon ansible_local.fleetinfo.previous_version
 « Vérifier qu'une version cible valide est connue »               format X.Y.Z
 « Lister les releases présentes sur le serveur »
 « Vérifier la présence de la release complète X »                 releases/X/health.json
 « Refuser un retour arrière vers une release absente ou incomplète »
 « Préparer l'arborescence de l'application »                      prepare.yml
 « Rebasculer sans régénération vers la release X »
   v
 deploy.yml avec fleetinfo_version: X, fleetinfo_render_release: false,
                 fleetinfo_deploy_kind: rollback-manuel
     bascule current -> releases/X, /health, fait local, journal (type=rollback-manuel)
     en cas d'échec : rescue identique au déploiement (retour sur la release quittée)
```

Après un retour arrière manuel, la release quittée devient la « précédente » : relancer
`rollback.yml` sans argument fait donc l'**aller-retour** entre les deux dernières releases
(vérifié en local : `1.2.0` → `1.1.0` → `1.2.0`). Les fichiers servis ne sont pas régénérés : la
page restaurée affiche la date de son déploiement initial.

Aligner ensuite `fleetinfo_version` dans `ansible/group_vars/all/vars.yml` sur la version
restaurée, sinon le prochain `site.yml` redéploie la version que l'on vient de quitter. Observé
sur le banc local le 2026-11-04 (`changed=3`) : une fois la version alignée, le premier
`site.yml` régénère sur place la
page et `health.json` de la release restaurée (date et version précédente reprises du fait
local), avec une ligne `type=mise-a-jour-sur-place` ; le passage suivant revient à `changed=0`.

---

## 9. Frontière Terraform / Ansible

```text
            TERRAFORM (poste)                          ANSIBLE (controller)
  ┌───────────────────────────────────┐      ┌───────────────────────────────────────┐
  │ Ce qui existe dans le projet GCP  │      │ Ce qui existe DANS le système         │
  │                                   │      │                                       │
  │ VPC, sous-réseau                  │      │ paquets (curl, vim, nginx, passlib...)│
  │ règles de firewall (tag réseau)   │      │ fuseau horaire, compte fleetops, motd │
  │ VM : nombre, type, image, disque  │      │ nginx.conf, site fleetinfo.conf       │
  │ IP publique éphémère              │      │ htpasswd de /status (Vault)           │
  │ labels, tag réseau                │      │ releases, lien current, /health       │
  │ métadonnées ssh-keys, OS Login    │      │ fait local, journal de déploiement    │
  └─────────────────┬─────────────────┘      └─────────────────────^─────────────────┘
                    │  Interface : labels, natIP, utilisateur      │
                    │  ansible + clé publique, port HTTP           │
                    └──────────────────────────────────────────────┘
       Jamais : Terraform n'installe aucun paquet (pas de startup-script).
       Jamais : Ansible ne crée ni ne supprime de ressource GCP (il ne fait que lire l'API).
```

La seule « colle » entre les deux est
[`scripts/prepare-cloud-inventory.sh`](../scripts/prepare-cloud-inventory.sh), qui transmet à
Ansible le `project_id` (output Terraform) et les identifiants de lecture de l'API. Les noms et
valeurs partagés sont listés dans le contrat d'interface de la
[section 5](#5-chaîne-de-linventaire-dynamique).

Conséquences pour l'exploitation :

| Changement | Outil | Suite |
|---|---|---|
| Nombre de VM, type de machine, image, disque, firewall, IP autorisée en SSH | Terraform (`terraform.tfvars` puis `terraform apply`) | `site.yml` pour configurer une nouvelle VM ; rien côté Ansible sinon. |
| Version de l'application, configuration nginx, mot de passe `/status`, paquets, fuseau horaire | Ansible (variables puis `site.yml`) | Rien côté Terraform. |
| Port HTTP | Les deux : `http_port` (Terraform) et `socle_http_port` (Ansible), plus les ports publiés dans `local/docker-compose.yml` | Voir [RB-04](runbooks.md#rb-04-modifier-la-configuration-du-serveur-web). |

---

## 10. Ce que possède chaque outil

| Outil | Où il tourne | Ce qu'il possède (source de vérité) | Ce qu'il ne fait pas |
|---|---|---|---|
| **Git** | Poste, GitHub | Tout le code, les modèles (`*.example`), le coffre chiffré `vault.yml`, le verrou `.terraform.lock.hcl`. | Aucun secret en clair, aucun state, aucune clé, aucun identifiant de session de lab. |
| **Terraform** (`~> 1.9`, provider `hashicorp/google` 8.9.0) | Poste | VPC, sous-réseau, 2 règles de firewall, N VM (labels, tag, métadonnées) ; state local `terraform/terraform.tfstate`. | Configuration du système, déploiement applicatif. |
| **gcloud** | Poste | Authentification de l'opérateur et Application Default Credentials. | Aucune création de ressource dans le socle (tout passe par Terraform). |
| **Docker Compose** | Poste | Banc local : images et conteneurs `controller`, `node1`, `node2`, réseau `labnet`, ports `8081` / `8082`. | Configuration des nœuds (faite par Ansible, comme sur une VM). |
| **Ansible** (`ansible-core` 2.17.14, dans le controller) | Controller | Tout l'état **interne** des serveurs : rôles `common`, `webserver`, `fleetinfo` ; inventaires ; coffre Vault. | Création de VM, de réseau ou de firewall. |
| **geerlingguy.nginx** 3.3.1 (Galaxy) | Controller (rôle) | Paquet nginx, `/etc/nginx/nginx.conf`, service nginx, suppression du site `default`. | Site Fleet Info et `/status` (rôle `webserver`, ADR-04). |
| **google.cloud** 1.15.0 (collection) | Controller | Plugin d'inventaire dynamique `google.cloud.gcp_compute` (lecture seule de l'API). | Aucune écriture dans GCP. |
| **community.general** 12.6.7 (collection) | Controller | Modules `community.general.timezone` (rôle `common`) et `community.general.htpasswd` (rôle `webserver`). | — |
| `local/scripts/generate-keys.sh` | Poste | Clé de déploiement ed25519 `local/ssh/fleet_key` (+ `.pub`, + copie dans `local/node/authorized_keys`). | — |
| `scripts/prepare-cloud-inventory.sh` | Poste | `ansible/inventories/cloud/fleet.gcp.yml` et `.secrets/gcp-adc.json` (générés, non versionnés). | — |
