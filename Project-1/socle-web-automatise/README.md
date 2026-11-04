# Socle Web Automatisé — documentation de transfert

- **Projet :** NovaRetail, équipe Plateforme. Déploiement de l'application *Fleet Info* sur
  Google Cloud (Terraform + Ansible) et en local (Docker Compose + Ansible).
- **Public :** consultant qui reprend l'exploitation (run) du socle. Il connaît Terraform,
  Ansible et GCP, mais ni ce projet, ni ses choix, ni ses conventions.
- **Point d'entrée unique :** ce README. Les documents de `docs/` et les README des rôles et des
  modules le complètent ; chaque section y renvoie quand un détail est nécessaire.

> **État au 2026-11-03.** L'environnement **local** est vérifié de bout en bout. L'environnement
> **cloud** est vérifié hors ligne (`terraform fmt`, `validate`, `plan`, inventaire dynamique
> testé sur une réponse simulée de l'API Compute Engine) mais **n'a pas encore été exécuté sur
> un vrai projet GCP** (session de lab expirée). Toutes les sorties cloud de ce document sont
> donc des **résultats attendus**, à confirmer lors de la répétition générale
> (voir [section 12](#12-définition-de-terminé)).

## Sommaire

1. [Présentation](#1-présentation)
2. [Architecture](#2-architecture)
3. [Structure du dépôt](#3-structure-du-dépôt)
4. [Prérequis et accès](#4-prérequis-et-accès)
5. [Déploiement de zéro](#5-déploiement-de-zéro)
   - [5.1 Environnement local](#51-environnement-local)
   - [5.2 Environnement cloud (GCP)](#52-environnement-cloud-gcp)
   - [5.3 Variante Windows](#53-variante-windows)
6. [Runbooks d'exploitation](#6-runbooks-dexploitation)
7. [Terraform](#7-terraform)
8. [Ansible](#8-ansible)
9. [Décisions techniques](#9-décisions-techniques)
10. [Où regarder en cas de problème](#10-où-regarder-en-cas-de-problème)
11. [Limites connues et dette technique](#11-limites-connues-et-dette-technique)
12. [Définition de « terminé »](#12-définition-de-terminé)
13. [Organisation de l'équipe et Git](#13-organisation-de-léquipe-et-git)

Documents complémentaires :

| Document | Contenu |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Schémas détaillés des deux environnements, flux réseau, chaîne de l'inventaire dynamique, cycle de vie d'un déploiement, frontière Terraform / Ansible |
| [docs/runbooks.md](docs/runbooks.md) | Les 7 runbooks d'exploitation (RB-01 à RB-07) et le retour arrière automatique (RB-08) |
| [docs/variables.md](docs/variables.md) | Référence de toutes les variables : où elles sont définies, ce qu'elles font, valeur par défaut |
| [docs/decisions.md](docs/decisions.md) | Décisions techniques ADR-01 à ADR-13 (justification, alternatives écartées) |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Journaux, fichiers générés, commandes de diagnostic, erreurs déjà rencontrées et leur solution |
| [docs/lab-gcp.md](docs/lab-gcp.md) | Contraintes de l'environnement de lab Google Skills |
| [docs/demo.md](docs/demo.md) | Script de la démonstration de soutenance |
| README des rôles : [common](ansible/roles/common/README.md), [webserver](ansible/roles/webserver/README.md), [fleetinfo](ansible/roles/fleetinfo/README.md) | Objectif, variables, dépendances, exemple d'utilisation de chaque rôle |
| README des modules : [network](terraform/modules/network/README.md), [compute](terraform/modules/compute/README.md) | Ressources, entrées et sorties de chaque module Terraform |

---

## 1. Présentation

### Objectif

L'équipe d'exploitation de NovaRetail gérait ses serveurs web à la main, sans retour arrière
possible. Le socle remplace ces opérations manuelles par du code :

- l'infrastructure GCP est **décrite en code** (Terraform) et reconstructible à l'identique ;
- la configuration des serveurs et le déploiement applicatif sont **automatisés et
  idempotents** (Ansible) : un second passage sur un serveur conforme ne change rien
  (`changed=0`) ;
- une mise en production qui échoue **revient automatiquement à la version précédente**, et le
  site reste en ligne ;
- les développeurs disposent d'un **environnement local** (Docker Compose) qui exécute **le même
  code Ansible** que le cloud ;
- **aucun secret** n'est versionné en clair (Ansible Vault, fichiers ignorés par Git).

### Périmètre

- **Application :** *Fleet Info*, page web générée par Ansible à partir des *facts* de chaque
  serveur : nom d'hôte et FQDN, adresses IP, distribution, noyau, vCPU, mémoire, environnement
  (`local` / `cloud`), version déployée, date du dernier déploiement ; sur GCP en plus : zone,
  type de machine, IP publique. Deux endpoints : `/health` (JSON : statut + version) et
  `/status` (`stub_status` de nginx, protégé par mot de passe).
- **Cloud :** un projet GCP de lab (temporaire) ; un VPC dédié, un sous-réseau, deux règles de
  firewall, N VM Debian 12 (N = `vm_count`, 2 dans le modèle `terraform.tfvars.example`), une
  seule zone.
- **Local :** un controller Ansible et deux nœuds Debian 12 (systemd, sshd) en conteneurs, qui
  se comportent comme des VM.

### Ce qui est automatisé et ce qui ne l'est pas

| Automatisé | Par |
|---|---|
| Création et destruction du VPC, du sous-réseau, des règles de firewall et des VM | Terraform |
| Labels et tag réseau des VM, injection de la clé SSH de déploiement (métadonnée `ssh-keys`) | Terraform |
| Banc local (images, conteneurs, réseau, ports publiés) | Docker Compose |
| Génération de la clé SSH de déploiement | `local/scripts/generate-keys.sh` |
| Génération de l'inventaire cloud et transmission des identifiants GCP au controller | `scripts/prepare-cloud-inventory.sh` |
| Découverte des VM (inventaire dynamique par labels) | Ansible, plugin `google.cloud.gcp_compute` |
| Socle système : paquets, fuseau horaire, compte d'exploitation, bannière | Ansible, rôle `common` |
| nginx, site Fleet Info, `/status` protégé, validation `nginx -t` avant rechargement | Ansible, rôles `geerlingguy.nginx` + `webserver` |
| Déploiement versionné, contrôle `/health`, retour arrière automatique, journal, ménage des releases | Ansible, rôle `fleetinfo` |
| Retour arrière manuel | Ansible, playbook `rollback.yml` |

| **Non automatisé** (action manuelle documentée) | Où c'est décrit |
|---|---|
| Démarrage du lab, relevé du `project_id`, du compte étudiant et des contraintes de la session | [docs/lab-gcp.md](docs/lab-gcp.md), étape [C1](#52-environnement-cloud-gcp) |
| Authentification `gcloud` (interactive, dans le navigateur) | Étape [C2](#52-environnement-cloud-gcp) |
| Saisie de `terraform/terraform.tfvars` (`project_id`, région, zone, nombre de VM, IP publique du poste) | Étape [C3](#52-environnement-cloud-gcp) |
| Transmission du mot de passe Vault (hors Git) | [Section 4](#mot-de-passe-ansible-vault) |
| Choix de la version à livrer (une variable) et commit | [RB-01](docs/runbooks.md#rb-01-déployer-une-nouvelle-version) |
| `terraform fmt` / `validate`, `ansible-lint` (aucune CI) | Sections [7](#7-terraform) et [8](#8-ansible) |
| Mises à jour de sécurité de l'OS, supervision, alerting, TLS, DNS, load balancer | Hors périmètre, voir [section 11](#11-limites-connues-et-dette-technique) |

---

## 2. Architecture

Principe : **Terraform crée l'infrastructure, Ansible la configure et y déploie l'application.**
Les deux outils ne se recouvrent jamais. Le **même** `site.yml`, les **mêmes** rôles et les
**mêmes** templates servent en local et sur le cloud : seuls l'inventaire et ses `group_vars`
diffèrent (ADR-01). Le controller Ansible est un conteneur qui tourne sur le poste de
l'opérateur et sert pour les deux environnements (ADR-02).

```text
 POSTE DE L'OPÉRATEUR (Windows / macOS / Linux)
┌──────────────────────────────────────────────────────────────────────────────┐
│ terraform, gcloud ──────────── HTTPS 443 ─────────────────> API Google Cloud │
│                                                                              │
│ Docker Compose « fleetinfo-local », réseau bridge « labnet »                 │
│ ┌──────────────────────────┐            ┌────────────┐   ┌────────────┐      │
│ │ controller               │            │ node1      │   │ node2      │      │
│ │ ansible-core 2.17.14     │            │ nginx :80  │   │ nginx :80  │      │
│ │ /workspace = le socle    │            └─────^──────┘   └─────^──────┘      │
│ └──────┬─────────┬─────────┘                  │                │             │
│        │         └────────── SSH 22 ──────────┴────────────────┘             │
│        │                    ports publiés : localhost:8081 -> node1:80       │
│        │                                    localhost:8082 -> node2:80       │
└────────┼─────────────────────────────────────────────────────────────────────┘
         │ SSH 22    (source = IP publique du poste, autorisée en /32)
         │ HTTPS 443 (API Compute Engine : inventaire dynamique)
         v
 GOOGLE CLOUD — projet temporaire du lab
┌──────────────────────────────────────────────────────────────────────────────┐
│ VPC fleetinfo-vpc ── sous-réseau fleetinfo-subnet-<région> (10.10.0.0/24)    │
│ firewall : fleetinfo-vpc-allow-http  tcp:80  depuis 0.0.0.0/0                │
│            fleetinfo-vpc-allow-ssh   tcp:22  depuis l'IP du poste en /32     │
│            (les deux ciblent le seul tag réseau fleetinfo-web)               │
│ ┌──────────────────┐ ┌──────────────────┐        ┌──────────────────┐        │
│ │ fleetinfo-web-1  │ │ fleetinfo-web-2  │  ...   │ fleetinfo-web-N  │        │
│ │ Debian 12, nginx │ │ Debian 12, nginx │        │ (N = vm_count)   │        │
│ └──────────────────┘ └──────────────────┘        └──────────────────┘        │
└──────────────────────────────────────────────────────────────────────────────┘
        ^ HTTP 80 depuis Internet : page Fleet Info, /health, /status
```

| Outil | Où il tourne | Rôle dans le socle |
|---|---|---|
| **Terraform** | Poste | VPC, sous-réseau, règles de firewall, VM (nombre, type, image, disque, labels, tag, métadonnées `ssh-keys`). State local. |
| **gcloud** | Poste | Authentification de l'opérateur ; Application Default Credentials (ADC) utilisées par Terraform et par l'inventaire dynamique. |
| **Docker Compose** | Poste | Banc local (`controller`, `node1`, `node2`) ; le controller sert aussi pour le cloud. |
| **Ansible** | Controller | Toute la configuration *dans* les serveurs et le déploiement de Fleet Info ; lecture seule de l'API Compute Engine pour l'inventaire. |
| **Git** | Poste, GitHub | Source de vérité du code ; aucun secret, state, clé ni identifiant de session. |

**Flux réseau.** Terraform et gcloud parlent aux API Google en HTTPS. Le controller lit l'API
Compute Engine (HTTPS) puis se connecte en SSH (22) à l'IP publique de chaque VM ; vu de GCP, ce
trafic vient de l'IP publique du poste (NAT Docker puis accès Internet du poste), seule source
autorisée par la règle SSH. En local, le controller joint `node1` et `node2` en SSH sur le
réseau Docker `labnet`. Les pages sont consultées en HTTP (80) : sur l'IP publique des VM, ou via
`localhost:8081` et `localhost:8082` en local. Le contrôle de santé `/health` est lancé **depuis
chaque serveur** sur `127.0.0.1`.

**Frontière Terraform / Ansible.** Terraform s'arrête quand la VM démarre avec un utilisateur
`ansible` et une clé publique autorisée : il n'installe aucun paquet (pas de `startup-script`).
Ansible ne crée ni ne supprime aucune ressource GCP : il lit l'API pour découvrir les VM (filtre
`labels.app = fleetinfo` et `status = RUNNING`) puis se connecte en SSH sur leur IP publique. Le
contrat entre les deux : labels `app` / `role` / `env`, IP publique (`natIP`), utilisateur
`ansible` et clé `fleet_key`, port HTTP 80.

Schémas détaillés (conteneurs, volumes, VPC, firewall, labels, flux numérotés, inventaire
dynamique, cycle de vie d'un déploiement, canari) : **[docs/architecture.md](docs/architecture.md)**.

---

## 3. Structure du dépôt

Le socle se trouve dans `Project-1/socle-web-automatise/` du dépôt Git de l'équipe. **Toutes les
commandes de ce README partent de ce dossier**, sauf mention contraire. Les éléments marqués
*(généré)* ne sont **pas versionnés** (`.gitignore`). Le détail des fichiers de chaque rôle et de
chaque module est dans son README.

```text
socle-web-automatise/
├── README.md                        Ce document (point d'entrée unique)
├── .gitignore                       Secrets, clés, state, tfvars, inventaire généré, dépendances Galaxy
├── .gitattributes                   Fins de ligne LF (*.sh, Dockerfile, *.yml, *.j2, ansible.cfg)
├── .devcontainer/devcontainer.json  Option VS Code : ouvrir le controller en Dev Container
├── .vault_pass                      (généré) Mot de passe Ansible Vault, transmis hors Git
├── .secrets/gcp-adc.json            (généré) ADC gcloud copiées pour le controller
├── docs/
│   ├── architecture.md              Schémas détaillés des deux environnements
│   ├── runbooks.md                  Runbooks d'exploitation RB-01 à RB-08
│   ├── variables.md                 Référence des variables
│   ├── decisions.md                 Décisions techniques ADR-01 à ADR-13
│   ├── troubleshooting.md           Diagnostic et erreurs connues
│   ├── lab-gcp.md                   Contraintes du lab Google Skills
│   └── demo.md                      Script de la démonstration
├── scripts/
│   └── prepare-cloud-inventory.sh   (poste, après apply) génère fleet.gcp.yml + copie les ADC
├── local/                           Banc local Docker Compose
│   ├── docker-compose.yml           Projet « fleetinfo-local » : controller, node1, node2
│   ├── controller/
│   │   ├── Dockerfile               python:3.12-slim + client SSH + dépendances épinglées
│   │   ├── requirements.txt         ansible-core, ansible-lint, google-auth, requests
│   │   ├── entrypoint.sh            Clé privée recopiée en 600 ; dépendances Galaxy si absentes
│   │   └── read-vault-password.sh   Lit .vault_pass pour Ansible (/usr/local/bin/fleet-vault-pass)
│   ├── node/
│   │   ├── Dockerfile               debian:bookworm-slim + systemd PID 1 + sshd + python3 + sudo
│   │   └── authorized_keys          (généré) Clé publique intégrée à l'image au build
│   ├── scripts/
│   │   └── generate-keys.sh         Génère la clé de déploiement ed25519 (idempotent)
│   └── ssh/fleet_key, fleet_key.pub (généré) Clé de déploiement (local ET cloud)
├── ansible/
│   ├── ansible.cfg                  Inventaire local par défaut, chemins, Vault, en-tête ansible_managed
│   ├── .ansible-lint                Profil « production »
│   ├── requirements.yml             Rôle et collections Galaxy, versions épinglées
│   ├── site.yml                     Point d'entrée : 3 plays (common, webserver, fleetinfo)
│   ├── rollback.yml                 Retour arrière manuel de Fleet Info
│   ├── group_vars/all/
│   │   ├── vars.yml                 Variables communes (dont fleetinfo_version)
│   │   └── vault.yml                Secrets chiffrés (Ansible Vault)
│   ├── inventories/
│   │   ├── local/
│   │   │   ├── hosts.yml            Inventaire statique : groupe web = node1, node2
│   │   │   └── group_vars/all.yml   Connexion SSH locale, socle_env: local
│   │   └── cloud/
│   │       ├── fleet.gcp.yml.example  Modèle versionné de l'inventaire dynamique
│   │       ├── fleet.gcp.yml          (généré) Inventaire dynamique de la session
│   │       └── group_vars/all.yml     Connexion SSH cloud, socle_env: cloud, zone, type, IP
│   ├── roles/
│   │   ├── common/                  Socle système (README, defaults, vars, tasks, handlers, templates, meta)
│   │   ├── webserver/               Site nginx Fleet Info + /status (même arborescence ;
│   │   │                            templates/ : fleetinfo.conf.j2, nginx.conf.j2 enveloppe)
│   │   ├── fleetinfo/               Déploiement versionné, /health, rollback
│   │   │                            (tasks/ : main, prepare, deploy, rollback, cleanup)
│   │   └── geerlingguy.nginx/       (généré) Rôle public installé par ansible-galaxy
│   └── collections/                 (généré) google.cloud, community.general
└── terraform/
    ├── versions.tf                  UNIQUE required_version / required_providers
    ├── providers.tf                 Provider google (project, region, zone)
    ├── variables.tf                 Variables racine (types, descriptions, validations)
    ├── locals.tf                    Labels des VM, clé publique, suffixe de port et chemin de clé des outputs
    ├── main.tf                      Instancie module.network et module.compute
    ├── outputs.tf                   Sorties d'exploitation
    ├── terraform.tfvars.example     Modèle des valeurs d'entrée (aucune valeur réelle)
    ├── .terraform.lock.hcl          Version exacte du provider (8.9.0), versionné
    ├── terraform.tfvars             (généré) Valeurs de la session de lab
    ├── terraform.tfstate            (généré) State local
    ├── .terraform/                  (généré) Provider téléchargé par terraform init
    └── modules/
        ├── network/                 VPC, sous-réseau, firewall (README, main, variables, outputs)
        └── compute/                 VM Compute Engine en count (README, main, variables, outputs)
```

Écarts assumés par rapport à la structure suggérée par les consignes (§5) :

| Structure suggérée | Structure réelle | Justification |
|---|---|---|
| `ansible/playbooks/` | Absent : les plays sont écrits dans `site.yml` ; `rollback.yml` est à côté | Les `group_vars` de playbook (`ansible/group_vars/all/`, dont le coffre) ne sont chargés que pour les playbooks situés dans le même dossier : avec des plays importés depuis `playbooks/`, `vault_webserver_status_password` était indéfinie. ADR-09. |
| `roles/nginx/` | `roles/webserver/` + rôle public `geerlingguy.nginx` | Nom autorisé par les consignes (« `nginx` (ou `webserver`) »). Le préfixe `webserver_` évite toute collision avec les variables `nginx_*` du rôle public. ADR-04. |
| `inventories/local/hosts.yml` | `inventories/local/hosts.yml` | Conforme (format YAML ; remplace le `hosts.ini` des premiers commits). Mêmes noms de groupes que le cloud (`web`). |
| `inventories/cloud/fleet.gcp.yml` | `fleet.gcp.yml.example` versionné ; `fleet.gcp.yml` généré par `scripts/prepare-cloud-inventory.sh` | L'option `projects` du plugin n'a pas de variable d'environnement : le fichier est généré pour que le `project_id` ne soit jamais versionné. ADR-07. |
| `terraform/network.tf`, `compute.tf` | `main.tf` + `modules/network/`, `modules/compute/` + `locals.tf` | TERRAFORM.md §1.5 impose des modules locaux ; `locals.tf` calcule les labels et lit la clé publique. ADR-12. |
| — | `scripts/`, `local/scripts/`, `local/controller/entrypoint.sh`, `local/controller/requirements.txt`, `.devcontainer/` | Ajouts : génération des clés, passage Terraform → Ansible, compatibilité Windows, versions Python épinglées, confort VS Code. |
| — | `roles/*/meta/argument_specs.yml` | Bonus : validation des variables d'entrée de chaque rôle. |

---

## 4. Prérequis et accès

### Outils sur le poste

| Outil | Version requise | Version testée (2026-11-03/04) | Usage | Vérification |
|---|---|---|---|---|
| Git | récente | 2.47.3 | Cloner le dépôt | `git --version` |
| Docker Desktop (Windows, macOS) ou Docker Engine + plugin Compose (Linux) | Compose v2+ (`docker compose`, option `--wait`), cgroups v2 | Docker Engine 29.9.2, Docker Compose v5.6.1 (VM Debian 13) | Banc local et controller Ansible (qui sert aussi pour le cloud) | `docker compose version` |
| Bash | Natif sous Linux / macOS ; WSL 2 ou Git Bash sous Windows | GNU bash (Debian 13) | `generate-keys.sh`, `prepare-cloud-inventory.sh` | `bash --version` |
| OpenSSH client (`ssh`, `ssh-keygen`) | récente (clés ed25519) | OpenSSH 10.0p2 | Génération de la clé, SSH d'exploitation | `ssh -V` |
| Terraform | `~> 1.9` (>= 1.9 et < 2.0), contrainte de `terraform/versions.tf` | 1.17.1 (`fmt`, `init`, `validate`, `plan` hors ligne) | Infrastructure GCP | `terraform version` |
| Google Cloud CLI (`gcloud`) | récente (`gcloud auth application-default login`) | 591.0.0 (pas encore utilisé contre un projet de lab pour ce socle) | Authentification, ADC | `gcloud --version` |
| `curl`, navigateur | — | — | Vérifications HTTP, IP publique IPv4 du poste (`curl -4`) | `curl --version` |

Ansible n'est **pas** à installer sur le poste : il tourne dans le conteneur controller, avec des
versions épinglées (ADR-02).

### Dans le controller

| Composant | Version | Défini dans |
|---|---|---|
| Python | 3.12 (image `python:3.12-slim` ; 3.12.14 testé) | `local/controller/Dockerfile` |
| ansible-core | 2.17.14 | `local/controller/requirements.txt` |
| ansible-lint | 25.9.2 | `local/controller/requirements.txt` |
| google-auth / requests | 2.62.1 / 2.34.2 | `local/controller/requirements.txt` |
| Collection `google.cloud` | 1.15.0 | `ansible/requirements.yml` |
| Collection `community.general` | 12.6.7 | `ansible/requirements.yml` |
| Rôle `geerlingguy.nginx` | 3.3.1 | `ansible/requirements.yml` |

### Comptes et droits

| Accès | Pourquoi | Comment l'obtenir |
|---|---|---|
| Lecture du dépôt Git | Cloner le code | Invitation sur le dépôt GitHub de l'équipe |
| Docker utilisable sans `sudo` ; conteneurs `privileged` autorisés | Les nœuds locaux exécutent systemd | Docker Desktop : par défaut. Linux : `sudo usermod -aG docker $USER` puis reconnexion |
| Compte de lab Google Skills (`student-XX-...@qwiklabs.net`) | Projet GCP temporaire, avec les droits de création réseau / firewall / VM accordés par le lab | Démarrer le lab (voir [docs/lab-gcp.md](docs/lab-gcp.md)) |
| Hors lab (projet GCP vierge) : rôles IAM du compte qui lance Terraform | Créer VPC, sous-réseau, firewall et VM | `roles/compute.networkAdmin`, `roles/compute.securityAdmin` (firewall), `roles/compute.instanceAdmin.v1`, plus `roles/serviceusage.serviceUsageAdmin` si l'API Compute doit être activée ; à défaut `roles/editor`. Inventaire dynamique seul : `roles/compute.viewer` |
| API Compute Engine activée sur le projet | Terraform et inventaire dynamique | En principe active dans le lab ; sinon `gcloud services enable compute.googleapis.com` |
| Mot de passe Ansible Vault | Déchiffrer `ansible/group_vars/all/vault.yml` | Transmis par l'équipe, hors Git (ci-dessous) |

Vérifier les rôles d'un compte sur un projet (poste) :

```bash
gcloud projects get-iam-policy "$PROJECT_ID" --flatten=bindings \
  --filter="bindings.members:user:$(gcloud config get-value account)" --format="value(bindings.role)"
```

### Mot de passe Ansible Vault

Le coffre `ansible/group_vars/all/vault.yml` est chiffré et versionné ; son mot de passe ne l'est
**jamais**. Il est remis par l'équipe Plateforme lors de la passation, **hors Git** (gestionnaire
de mots de passe ou canal chiffré convenu ; jamais par ticket, e-mail ou messagerie en clair).

Créer le fichier `.vault_pass` à la racine du socle. Dans le controller, il est lu par le script
`/usr/local/bin/fleet-vault-pass` (variable `ANSIBLE_VAULT_PASSWORD_FILE`, insensible aux droits
`777` des montages Windows) ; hors controller, par `vault_password_file = ../.vault_pass`
d'`ansible.cfg` :

```bash
printf '%s' 'MOT_DE_PASSE_VAULT_TRANSMIS_PAR_L_EQUIPE' > .vault_pass && chmod 600 .vault_pass
```

Résultat attendu : `ls -l .vault_pass` affiche `-rw-------` ; `git check-ignore .vault_pass`
renvoie `.vault_pass` (fichier ignoré par Git). Le mot de passe est vérifié plus loin, dans le
controller (étape [L5](#51-environnement-local)).

La variable du coffre utilisée par le code est `vault_webserver_status_password` (mot de passe de
la page `/status`, 24 caractères aléatoires), référencée par son nom dans
`ansible/group_vars/all/vars.yml` (ADR-11). Rotation des deux mots de passe :
[RB-05](docs/runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).

### Contraintes du lab GCP (résumé)

Détail et relevés de session : **[docs/lab-gcp.md](docs/lab-gcp.md)**.

- **Durée limitée** : le projet et tout son contenu sont supprimés en fin de session. Durée non
  encore relevée (pages du lab accessibles uniquement après connexion ; à compléter lors de la
  prochaine session). La reconstruction complète doit tenir largement dans ce temps.
- **Identifiants changeants** : `project_id` et compte étudiant changent à chaque session. Ils ne
  sont écrits que dans `terraform/terraform.tfvars` et dans l'inventaire généré, tous deux non
  versionnés.
- **Périmètre restreint** : session précédente observée en région `us-central1`, zone
  `us-central1-f` ; types `e2-small` (défaut du socle) et `e2-medium` utilisés dans les labs du
  cours. Vérifier les contraintes affichées par le lab à chaque session.
- **Poste de contrôle** : Terraform et `gcloud` s'exécutent sur le poste ; **ne pas utiliser
  Cloud Shell** (son contenu est perdu à la fin du lab).
- Ouvrir la console du lab dans une **fenêtre de navigation privée** pour ne pas mélanger le
  compte étudiant avec un compte Google personnel.

---

## 5. Déploiement de zéro

Ordre conseillé : **local d'abord** (il produit la clé SSH et le controller utilisés ensuite par
le cloud), puis cloud. Chaque étape indique où la lancer : *(poste)* ou *(controller)*.

### 5.1 Environnement local

**L1. Cloner le dépôt** (poste)

```bash
git clone https://github.com/MartinFraysse/cloud-ia-project.git
cd cloud-ia-project/Project-1/socle-web-automatise
```

Résultat attendu : `ls` affiche `README.md  ansible  docs  local  scripts  terraform`.

**L2. Générer la clé SSH de déploiement** (poste, une seule fois)

```bash
./local/scripts/generate-keys.sh
```

Résultat attendu (extrait) :

```text
Generating public/private ed25519 key pair.
...
Clé publique copiée dans local/node/authorized_keys (intégrée aux nœuds au prochain build).
```

Le script est idempotent : relancé, il affiche `Clé déjà présente : .../local/ssh/fleet_key
(conservée).` En cas de `Permission non accordée` (bit exécutable perdu) :
`bash local/scripts/generate-keys.sh`.

**L3. Créer le fichier du mot de passe Vault** (poste) — voir [section 4](#mot-de-passe-ansible-vault)

```bash
printf '%s' 'MOT_DE_PASSE_VAULT_TRANSMIS_PAR_L_EQUIPE' > .vault_pass && chmod 600 .vault_pass
```

**L4. Construire et démarrer le banc** (poste)

```bash
cd local && docker compose up -d --build --wait
docker compose ps
```

Résultat attendu : le premier build télécharge environ 1 Go d'images. La commande rend la main
quand `node1` et `node2` sont *healthy* (sshd démarré par systemd) et que le controller est
démarré. `docker compose ps` affiche ensuite (extrait, colonnes IMAGE, COMMAND et CREATED
omises) :

```text
NAME                           SERVICE      STATUS                       PORTS
fleetinfo-local-controller-1   controller   Up About a minute
fleetinfo-local-node1-1        node1        Up About a minute (healthy)  0.0.0.0:8081->80/tcp
fleetinfo-local-node2-1        node2        Up About a minute (healthy)  0.0.0.0:8082->80/tcp
```

Selon la configuration IPv6 du moteur Docker, la colonne PORTS peut aussi afficher
`[::]:8081->80/tcp` : c'est sans conséquence. Le controller n'a pas de healthcheck : seul
`Up` est attendu pour lui.

**L5. Entrer dans le controller et vérifier les dépendances Galaxy** (poste, puis controller)

```bash
docker compose exec controller bash
```

On arrive dans `/workspace/ansible` (le dossier `socle-web-automatise/` du poste est monté sur
`/workspace`). Dans le controller :

```bash
ansible --version | head -2
ansible-galaxy install -r requirements.yml
ansible-vault view group_vars/all/vault.yml
```

Résultat attendu :

- `ansible [core 2.17.14]` puis `config file = /workspace/ansible/ansible.cfg` ;
- les dépendances sont **déjà installées** : au premier démarrage, l'entrypoint du controller a
  lancé lui-même `ansible-galaxy install -r requirements.yml` (visible avec
  `docker compose logs controller` : `geerlingguy.nginx (3.3.1) was installed successfully`,
  `google.cloud:1.15.0 was installed successfully`,
  `community.general:12.6.7 was installed successfully`). Elles sont dans `ansible/roles/` et
  `ansible/collections/`, donc conservées sur le poste entre deux démarrages. La commande
  manuelle, idempotente, sert de vérification ou de rattrapage (installation impossible sans
  Internet au démarrage) : elle indique `is already installed, skipping` et
  `Nothing to do. All requested collections are already installed.` ;
- `ansible-vault view` affiche, sans demander de mot de passe, `vault_webserver_status_password: ...` :
  le fichier `.vault_pass` est correct. Cette commande affiche un secret en clair : ne pas la
  lancer en partage d'écran. Si un pager s'ouvre, sortir avec `q`.

**L6. Vérifier l'inventaire et la connectivité** (controller)

```bash
ansible-inventory --graph
ansible web -m ansible.builtin.ping
```

Résultat attendu :

```text
@all:
  |--@ungrouped:
  |--@web:
  |  |--node1
  |  |--node2
```

puis `node1 | SUCCESS` et `node2 | SUCCESS`, avec `"ping": "pong"`.

**L7. Premier déploiement** (controller)

```bash
ansible-playbook site.yml
```

Résultat attendu : les plays « Appliquer le socle système commun » et « Configurer le serveur
web nginx » traitent `node1` et `node2` ensemble ; le play « Déployer l'application Fleet Info »
traite `node1` seul (canari) puis `node2`. Dans le `PLAY RECAP` : `changed` supérieur à 0 et
`failed=0` pour les deux nœuds.

**L8. Second passage : idempotence** (controller)

```bash
ansible-playbook site.yml
```

Résultat attendu : `changed=0` et `failed=0` pour `node1` et `node2`, aucun handler exécuté
(observé le 2026-11-03 : `ok=39 changed=0` sur chaque nœud).

**L9. Vérifier les pages** (poste, dans un autre terminal ou après `exit`)

```bash
curl -s http://localhost:8081/health
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/status
```

Résultat attendu (la date `deployed_at` est celle de votre déploiement) :

```json
{
  "_ansible_managed": "Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement",
  "_source": "roles/fleetinfo/templates/health.json.j2",
  "status": "ok",
  "application": "fleetinfo",
  "version": "1.0.0",
  "environment": "local",
  "hostname": "node1",
  "deployed_at": "2026-11-03T18:13:25Z"
}
```

puis `401` pour `/status` sans identifiants. Ouvrir http://localhost:8081 et
http://localhost:8082 dans un navigateur : deux pages différentes (nom d'hôte, adresses IP),
badge « Environnement : local », pas de section « Cloud ». Accès authentifié à `/status`, avec
la valeur de `vault_webserver_status_password` affichée à l'étape L5 :

```bash
curl -u exploitation:'MOT_DE_PASSE_LU_DANS_LE_COFFRE' http://localhost:8081/status
```

Résultat attendu : `Active connections: ...`, `server accepts handled requests`, puis
`Reading: ... Writing: ... Waiting: ...`.

Arrêter le banc sans le détruire : `docker compose stop` (depuis `local/`). Le supprimer :
`docker compose down` (la clé, `.vault_pass` et les dépendances Galaxy restent sur le poste).

### 5.2 Environnement cloud (GCP)

> Les sorties ci-dessous sont des **résultats attendus** : le déroulé complet sur un vrai projet
> GCP reste à valider lors de la répétition générale.

Prérequis : étapes L1 à L5 faites sur ce poste (clé `local/ssh/fleet_key.pub` présente, fichier
`.vault_pass` créé, dépendances Galaxy installées). Sans la clé publique, Terraform refuse de
planifier (`Clé publique introuvable : lancer local/scripts/generate-keys.sh...`).

**C1. Démarrer le lab et relever la session** (navigateur)

Démarrer le lab Google Skills, noter le `project_id` (`qwiklabs-gcp-...`), le compte étudiant, la
durée, la région et la zone autorisées. Voir [docs/lab-gcp.md](docs/lab-gcp.md).

**C2. Authentifier gcloud** (poste)

```bash
PROJECT_ID=qwiklabs-gcp-00-0123456789ab   # à remplacer par le project_id du panneau du lab
gcloud auth login
gcloud config set project "$PROJECT_ID"
gcloud auth application-default login
```

Résultat attendu : `You are now logged in as [student-XX-...@qwiklabs.net].`,
`Updated property [core/project].`, puis
`Credentials saved to file: [.../.config/gcloud/application_default_credentials.json]`.
Choisir le compte **du lab** dans les deux fenêtres d'authentification du navigateur.

Contrôle : `gcloud config get-value project` renvoie le `project_id` de la session.

**C3. Renseigner les variables Terraform** (poste)

```bash
cd terraform && cp terraform.tfvars.example terraform.tfvars
curl -4 -s https://ifconfig.me ; echo
```

Éditer `terraform/terraform.tfvars` : `project_id`, `region`, `zone`, `vm_count` et
`ssh_source_ranges = ["<IP affichée par curl>/32"]`. Exemple :

```hcl
project_id        = "qwiklabs-gcp-00-0123456789ab"
region            = "us-central1"
zone              = "us-central1-f"
vm_count          = 2
ssh_source_ranges = ["203.0.113.10/32"]
```

Les autres variables ont des valeurs par défaut adaptées au lab (tableau en
[section 7](#variables-racine-terraformvariablestf)).

**C4. Créer l'infrastructure** (poste, dossier `terraform/`)

```bash
terraform init && terraform plan && terraform apply && terraform plan
```

Résultat attendu :

- `init` : `Installing hashicorp/google v8.9.0...` puis `Terraform has been successfully initialized!` ;
- premier `plan` : `Plan: 6 to add, 0 to change, 0 to destroy.` (VPC, sous-réseau, 2 règles de
  firewall, 2 VM) ; la plage SSH apparaît comme `source_ranges = (sensitive value)` (vérifié hors
  ligne) ;
- `apply` (répondre `yes`) : `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.` suivi
  des outputs (`fleetinfo_urls`, `vm_public_ips`, `network_name`, `subnet_name`...) ;
- second `plan` : `No changes. Your infrastructure matches the configuration.`

**C5. Préparer l'inventaire dynamique** (poste, dossier `socle-web-automatise/`)

```bash
cd .. && ./scripts/prepare-cloud-inventory.sh
```

Résultat attendu :

```text
Inventaire généré : ansible/inventories/cloud/fleet.gcp.yml (projet qwiklabs-gcp-00-0123456789ab)
Identifiants copiés : .secrets/gcp-adc.json (lus par le controller)
```

**C6. Ouvrir le controller** (poste)

```bash
cd local && docker compose up -d --wait && docker compose exec controller bash
```

Résultat attendu : invite du controller dans `/workspace/ansible`. Si le controller tournait
déjà, il voit immédiatement les fichiers générés à l'étape C5 (montage du dépôt).

**C7. Vérifier l'inventaire dynamique** (controller)

```bash
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
```

Résultat attendu (l'ordre des groupes peut varier) :

```text
@all:
  |--@ungrouped:
  |--@web:
  |  |--fleetinfo-web-1
  |  |--fleetinfo-web-2
  |--@env_cloud:
  |  |--fleetinfo-web-1
  |  |--fleetinfo-web-2
  |--@zone_us_central1_f:
  |  |--fleetinfo-web-1
  |  |--fleetinfo-web-2
```

**C8. Vérifier la connectivité SSH** (controller)

Attendre environ une minute après `terraform apply` (l'agent invité GCE crée l'utilisateur
`ansible` au démarrage), puis :

```bash
ansible -i inventories/cloud/fleet.gcp.yml web -m ansible.builtin.ping
```

Résultat attendu : `fleetinfo-web-1 | SUCCESS` et `fleetinfo-web-2 | SUCCESS`, avec
`"ping": "pong"`. La clé d'hôte de chaque nouvelle VM est acceptée automatiquement à la première
connexion (`StrictHostKeyChecking=accept-new`).

**C9. Déployer, puis vérifier l'idempotence** (controller)

```bash
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
```

Résultat attendu : premier passage `changed` supérieur à 0, `failed=0` (canari d'abord, puis les
autres VM) ; second passage `changed=0`, `failed=0` sur toutes les VM.

**C10. Vérifier le service** (poste, dossier `socle-web-automatise/`)

Le terminal du poste est resté dans `local/` depuis l'étape C6 : après `exit` du controller (ou
dans un autre terminal), revenir à la racine du socle.

```bash
cd ..        # depuis local/ : retour dans socle-web-automatise/
terraform -chdir=terraform output fleetinfo_urls
curl -s http://203.0.113.21/health
ssh -i local/ssh/fleet_key ansible@203.0.113.21
```

Remplacer `203.0.113.21` par une IP affichée par `fleetinfo_urls` (répondre `yes` à la question
sur la clé d'hôte lors de la première connexion depuis le poste). Résultat attendu : une URL par
VM ; `/health` renvoie `"status": "ok"`, `"environment": "cloud"` et la version déployée ; la
page affiche une section « Cloud · Google Compute Engine » avec la zone et le type de machine, et
des informations différentes d'une VM à l'autre. Sur la VM, `/etc/motd` s'affiche à la connexion
et `head -2 /etc/nginx/sites-enabled/fleetinfo.conf` montre l'en-tête
`# Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN ...`. Depuis le
controller, la même connexion se fait avec `ssh -i /root/.ssh/fleet_key ansible@<IP>`.

**C11. Détruire l'environnement en fin de session** (poste, dossier `socle-web-automatise/`)

```bash
terraform -chdir=terraform destroy
rm -f ansible/inventories/cloud/fleet.gcp.yml
rm -rf .secrets
```

Résultat attendu : après `yes`, `Destroy complete! Resources: 6 destroyed.` Ne pas supprimer
`local/ssh/` avant le `destroy` : la validation de `ssh_public_key_path` exige la présence de la
clé publique, y compris pour détruire. Procédure complète et vérifications :
[RB-07](docs/runbooks.md#rb-07-détruire-lenvironnement-proprement).

### 5.3 Variante Windows

| Point | Consigne |
|---|---|
| Docker | Docker Desktop avec le moteur WSL 2 (les nœuds utilisent `privileged` et `cgroup: host` pour systemd). Sous WSL, activer l'intégration de Docker Desktop pour la distribution utilisée (*Settings > Resources > WSL integration*). |
| Shell pour les scripts | **WSL 2 (recommandé)** : cloner le dépôt *dans* le système de fichiers de la distribution (`~/...`, pas `/mnt/c/...`) et y exécuter toutes les commandes de ce README, avec `terraform` et `gcloud` installés dans WSL. Alternative : **Git Bash** (fournit `bash`, `ssh-keygen`, `sed`, `install`) ; les commandes `docker compose` fonctionnent aussi depuis PowerShell. |
| Terminal interactif | Si Git Bash répond `the input device is not a TTY` à `docker compose exec controller bash`, préfixer la commande par `winpty` ou la lancer depuis PowerShell / Windows Terminal. |
| Fins de ligne | `.gitattributes` force LF pour `*.sh`, `Dockerfile`, `*.yml`, `*.j2` et `ansible.cfg` ; un script extrait en CRLF échouerait dans les conteneurs (`/bin/sh^M: bad interpreter`). |
| Script non exécutable | `bash local/scripts/generate-keys.sh` et `bash scripts/prepare-cloud-inventory.sh`. |
| `ansible.cfg` ignoré | Déjà traité : `ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg` est positionné dans le controller (Ansible ignore un `ansible.cfg` situé dans un dossier accessible en écriture à tous, cas des montages Windows). |
| Clé SSH en `777` | Déjà traité : l'entrypoint du controller recopie la clé en `600` dans `/root/.ssh/fleet_key`. Pour se connecter en SSH à une VM, préférer le controller (`ssh -i /root/.ssh/fleet_key ansible@<IP>`). |
| ADC sous Git Bash | `gcloud` pour Windows range les ADC dans `%APPDATA%\gcloud\` : `prepare-cloud-inventory.sh` y cherche automatiquement (non rejoué sous Windows). En dernier recours : `GOOGLE_APPLICATION_CREDENTIALS="$APPDATA/gcloud/application_default_credentials.json" ./scripts/prepare-cloud-inventory.sh` (voir [docs/troubleshooting.md](docs/troubleshooting.md), erreur 15). Inutile sous WSL. |
| `.vault_pass` sous Git Bash (dépôt sur `C:\`) | Déjà traité : un fichier monté apparaît exécutable (`777`) et Ansible l'exécuterait comme un script ; le controller ne le désigne donc pas directement mais via le script `/usr/local/bin/fleet-vault-pass` (`ANSIBLE_VAULT_PASSWORD_FILE`), qui le **lit** (non rejoué sous Windows ; voir [docs/troubleshooting.md](docs/troubleshooting.md), erreur 19). |

---

## 6. Runbooks d'exploitation

Chaque runbook de **[docs/runbooks.md](docs/runbooks.md)** donne : quand l'utiliser, les
prérequis, les commandes, comment vérifier le résultat et quoi faire en cas d'échec. Toutes les
commandes Ansible se lancent dans le controller, depuis `/workspace/ansible` ; ajouter
`-i inventories/cloud/fleet.gcp.yml` pour le cloud.

| Runbook | Opération | Quand l'utiliser | Commande principale |
|---|---|---|---|
| [RB-01](docs/runbooks.md#rb-01-déployer-une-nouvelle-version) | Déployer une nouvelle version de l'application | Livraison d'une release `X.Y.Z` | Modifier `fleetinfo_version` dans `ansible/group_vars/all/vars.yml` (seul endroit), puis `ansible-playbook site.yml --tags fleetinfo` |
| [RB-02](docs/runbooks.md#rb-02-revenir-à-une-version-précédente) | Revenir manuellement à une version précédente | Régression constatée après un déploiement **réussi** | **Recommandé** : remettre l'ancienne valeur de `fleetinfo_version` (Git) puis `site.yml`. **Urgence** : `ansible-playbook rollback.yml` (ou `-e fleetinfo_rollback_version=1.0.0`), puis aligner `fleetinfo_version` |
| [RB-03](docs/runbooks.md#rb-03-ajouter-ou-retirer-un-serveur) | Ajouter (ou retirer) un serveur | Montée ou baisse de capacité | Cloud : `vm_count` dans `terraform.tfvars`, `terraform apply`, puis `site.yml` (aucune modification d'Ansible). Local : service `node3` dans `docker-compose.yml` + `hosts.yml` + `depends_on` |
| [RB-04](docs/runbooks.md#rb-04-modifier-la-configuration-du-serveur-web) | Modifier la configuration du serveur web | Port, filtrage IP de `/status`, réglages `nginx_*`... | Modifier la variable, puis `ansible-playbook site.yml --tags webserver` |
| [RB-05](docs/runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault) | Changer le mot de passe de `/status` et le mot de passe Vault | Rotation périodique, départ d'un membre, fuite suspectée | `ansible-vault edit group_vars/all/vault.yml` puis `--tags webserver` ; `ansible-vault rekey --new-vault-password-file /chemin/nouveau group_vars/all/vault.yml` puis remplacer `../.vault_pass` |
| [RB-06](docs/runbooks.md#rb-06-vérifier-la-conformité-dun-serveur) | Vérifier l'état de conformité d'un serveur | Audit, suspicion de modification manuelle, avant une livraison | `ansible-playbook site.yml --check --diff` (attendu : `changed=0`) |
| [RB-07](docs/runbooks.md#rb-07-détruire-lenvironnement-proprement) | Détruire l'environnement proprement | Fin de session de lab, fin de démonstration | `terraform -chdir=terraform destroy`, suppression de `fleet.gcp.yml` et `.secrets/` ; local : `docker compose down` |
| [RB-08](docs/runbooks.md#rb-08-rollback-automatique-et-simulation-déchec) | Retour arrière automatique (démonstration) | Prouver le rollback par un échec volontaire | `ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true` (version **différente** de la version active, sinon un garde-fou refuse) |

Comportement de la démonstration d'échec (vérifié en local le 2026-11-03, avec `1.1.0` active) :
la release `1.2.0` est livrée sans `health.json`, `/health` répond `404` (le message
`FAILED - RETRYING` s'affiche 5 fois, à 2 s d'intervalle) ; le `rescue` rebascule `current` vers
`1.1.0`, recharge nginx, revérifie `/health` puis fait échouer le play avec un message explicite.
Le canari affiche `failed=1 rescued=1`, l'autre serveur n'est jamais touché, le site reste en
ligne en `1.1.0` et l'échec est tracé dans `/var/log/fleetinfo/deploy.log` :

```text
2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
```

Un déploiement sain de `1.2.0` (sans `fleetinfo_simulate_failure`) fonctionne ensuite normalement.

---

## 7. Terraform

### Ressources et modules

`terraform/main.tf` ne déclare **aucune ressource** : il instancie deux modules locaux et relie la
sortie `subnet_id` du module réseau à l'entrée `subnetwork_id` du module VM (ADR-12). Détail de
chaque module : [modules/network/README.md](terraform/modules/network/README.md),
[modules/compute/README.md](terraform/modules/compute/README.md).

| Module | Ressource | Nom GCP (valeurs par défaut) | Rôle |
|---|---|---|---|
| `network` | `google_compute_network.this` | `fleetinfo-vpc` | VPC dédié en mode custom (`auto_create_subnetworks = false`), pas le réseau `default`. |
| `network` | `google_compute_subnetwork.this` | `fleetinfo-subnet-<region>` (ex. `fleetinfo-subnet-us-central1`) | Sous-réseau des VM, plage `subnet_cidr` (`10.10.0.0/24`). |
| `network` | `google_compute_firewall.allow_http` | `fleetinfo-vpc-allow-http` | INGRESS `tcp:<http_port>` (80) depuis `http_source_ranges` (`0.0.0.0/0`), vers le tag `network_tag`. |
| `network` | `google_compute_firewall.allow_ssh` | `fleetinfo-vpc-allow-ssh` | INGRESS `tcp:<ssh_port>` (22) depuis `ssh_source_ranges` (IP de l'opérateur en `/32`), vers le tag `network_tag`. |
| `compute` | `google_compute_instance.this[count]` | `fleetinfo-web-1` ... `fleetinfo-web-N` | VM Debian 12 (`count = vm_count`) : IP publique éphémère (`access_config {}`), tag réseau, labels `app` / `env` / `role` / `team`, métadonnées `ssh-keys` (`ansible:<clé publique>`) et `enable-oslogin = FALSE`, disque supprimé avec la VM (`auto_delete = true`), `allow_stopping_for_update = true`. Aucun `startup-script`, aucun bloc `service_account`. |

Avec `vm_count = 2` : **6 ressources**. Passer de 2 à 3 VM ne demande que `vm_count = 3` ;
réduire le nombre supprime les VM de plus fort indice (`count`).

`terraform/locals.tf` calcule `vm_labels` (`app = var.app_name`, `env = var.environment`,
`role = var.server_role`, `team = var.team`) et `ssh_public_key`
(`trimspace(file(var.ssh_public_key_path))`).

Le socle ne crée **pas** : IP statique, load balancer, DNS, Cloud NAT, bucket de state, compte de
service (voir [section 11](#11-limites-connues-et-dette-technique)).

### Variables racine (`terraform/variables.tf`)

Valeurs concrètes dans `terraform/terraform.tfvars` (copié depuis `terraform.tfvars.example`,
non versionné). Les cinq premières, propres à la session de lab, n'ont **pas** de valeur par
défaut.

| Variable | Description | Type | Défaut | Sensible | Validation |
|---|---|---|---|---|---|
| `project_id` | Identifiant du projet GCP de la session de lab | `string` | aucun (obligatoire) | non | Format GCP `^[a-z][a-z0-9-]{4,28}[a-z0-9]$` |
| `region` | Région GCP du sous-réseau (imposée ou autorisée par le lab) | `string` | aucun (obligatoire) | non | — |
| `zone` | Zone GCP des VM | `string` | aucun (obligatoire) | non | Doit appartenir à `region` (préfixe `<region>-`) |
| `vm_count` | Nombre de VM web | `number` | aucun (obligatoire) | non | Entier entre 2 et 10 |
| `ssh_source_ranges` | Plages CIDR autorisées en SSH : IP publique du poste en `/32` | `list(string)` | aucun (obligatoire) | **oui** | CIDR IPv4 de préfixe `/16` minimum (`0.0.0.0/0`, `0.0.0.0/1`, IPv6 refusés) |
| `name_prefix` | Préfixe des noms de ressources (VPC, sous-réseau, firewall, VM) | `string` | `"fleetinfo"` | non | `^[a-z][a-z0-9-]{1,20}$` |
| `subnet_cidr` | Plage CIDR du sous-réseau des VM | `string` | `"10.10.0.0/24"` | non | CIDR IPv4 valide |
| `http_port` | Port HTTP ouvert sur les VM (doit correspondre à `socle_http_port` côté Ansible) | `number` | `80` | non | — |
| `ssh_port` | Port SSH ouvert aux seules plages `ssh_source_ranges` | `number` | `22` | non | — |
| `http_source_ranges` | Plages CIDR autorisées en HTTP | `list(string)` | `["0.0.0.0/0"]` | non | — |
| `network_tag` | Tag réseau commun des VM, seule cible des règles de firewall | `string` | `"fleetinfo-web"` | non | — |
| `machine_type` | Type de machine Compute Engine (vérifier ceux autorisés par le lab) | `string` | `"e2-small"` | non | — |
| `vm_image` | Image de démarrage (famille Debian 12 maintenue par Google) | `string` | `"debian-cloud/debian-12"` | non | — |
| `boot_disk_size_gb` | Taille du disque de démarrage, en Go | `number` | `10` | non | — |
| `boot_disk_type` | Type du disque (`pd-standard`, `pd-balanced`, `pd-ssd`) | `string` | `"pd-balanced"` | non | — |
| `ssh_user` | Utilisateur créé par l'agent invité GCE (métadonnée `ssh-keys`) ; c'est l'`ansible_user` du cloud | `string` | `"ansible"` | non | — |
| `ssh_public_key_path` | Chemin de la clé publique injectée dans les VM | `string` | `"../local/ssh/fleet_key.pub"` | non | Le fichier doit exister |
| `environment` | Valeur du label `env` (groupe Ansible `env_<valeur>`) | `string` | `"cloud"` | non | — |
| `server_role` | Valeur du label `role` (groupe Ansible du même nom, ciblé par `site.yml`) | `string` | `"web"` | non | — |
| `team` | Valeur du label `team` (équipe propriétaire) | `string` | `"plateforme"` | non | — |
| `app_name` | Valeur du label `app` : filtre de l'inventaire dynamique | `string` | `"fleetinfo"` | non | — |

Validations testées hors ligne le 2026-11-03 : `0.0.0.0/0` en SSH refusé, zone hors région
refusée, `vm_count = 0` refusé.

> `ssh_source_ranges` est masquée dans `plan` / `apply` (`(sensitive value)`), mais reste lisible
> dans `terraform.tfvars` et dans le state, tous deux non versionnés. Changer `app_name`,
> `server_role` ou `ssh_user` impose d'adapter Ansible (filtre de `fleet.gcp.yml.example`,
> `hosts: web`, `ansible_user`) : voir le contrat d'interface dans
> [docs/architecture.md](docs/architecture.md#5-chaîne-de-linventaire-dynamique).

Variables d'entrée des modules (toutes obligatoires sauf mention) :

| Module | Variables (`modules/<module>/variables.tf`) | Alimentées par `main.tf` |
|---|---|---|
| `network` | `network_name`, `subnet_name`, `region`, `subnet_cidr`, `target_tag`, `http_port`, `http_source_ranges` (`list(string)`), `ssh_port`, `ssh_source_ranges` (`list(string)`, **sensible**) | `network_name = "${var.name_prefix}-vpc"`, `subnet_name = "${var.name_prefix}-subnet-${var.region}"`, `target_tag = var.network_tag`, les autres avec la variable racine du même nom |
| `compute` | `instance_count`, `name_prefix`, `zone`, `machine_type`, `image`, `disk_size_gb`, `disk_type`, `subnetwork_id`, `network_tags` (`list(string)`), `labels` (`map(string)`, doit contenir `env`, `role`, `team`), `ssh_user`, `ssh_public_key`, `enable_os_login` (`bool`, défaut `false`) | `instance_count = var.vm_count`, `name_prefix = "${var.name_prefix}-${var.server_role}"`, `image = var.vm_image`, `disk_size_gb = var.boot_disk_size_gb`, `disk_type = var.boot_disk_type`, `subnetwork_id = module.network.subnet_id`, `network_tags = [var.network_tag]`, `labels = local.vm_labels`, `ssh_public_key = local.ssh_public_key` ; `zone`, `machine_type` et `ssh_user` avec la variable racine du même nom ; `enable_os_login` non transmis (défaut `false`) |

### Providers et versions épinglées

| Élément | Contrainte (`terraform/versions.tf`) | Version figée (`terraform/.terraform.lock.hcl`, versionné) |
|---|---|---|
| Terraform | `required_version = "~> 1.9"` (les validations qui référencent une autre variable, comme zone / région, exigent Terraform 1.9) | — |
| Provider `hashicorp/google` | `version = "~> 8.9"` | `8.9.0`, avec les empreintes `h1:` de plusieurs plateformes |

`required_providers` n'existe qu'une fois dans le socle, dans `versions.tf` (aucun dans les
modules). La configuration du provider (`terraform/providers.tf`) se limite à `project`,
`region` et `zone`, issus des variables ; l'authentification passe par les ADC du poste
(`gcloud auth application-default login`), sans clé de compte de service.

Contrôles qualité (vérifiés le 2026-11-03), depuis `terraform/`. `validate` exige un
`terraform init` préalable ; ni l'un ni l'autre n'a besoin d'un projet GCP ni d'identifiants.

```bash
terraform fmt -check -recursive     # aucune sortie, code retour 0
terraform init                      # une fois : télécharge le provider figé par le lock
terraform validate                  # Success! The configuration is valid.
```

### Outputs (`terraform/outputs.tf`)

Lecture : `terraform -chdir=terraform output` (tous) ou `terraform -chdir=terraform output <nom>`.
Aucun output n'est sensible. Les exemples ci-dessous sont des valeurs attendues.

| Output | Ce qu'il renvoie | Exemple |
|---|---|---|
| `network_name` | Nom du VPC | `"fleetinfo-vpc"` |
| `subnet_name` | Nom du sous-réseau | `"fleetinfo-subnet-us-central1"` |
| `subnet_cidr` | Plage CIDR du sous-réseau | `"10.10.0.0/24"` |
| `firewall_rules` | Noms des règles de firewall | `["fleetinfo-vpc-allow-http", "fleetinfo-vpc-allow-ssh"]` |
| `network_tag` | Tag réseau des VM | `"fleetinfo-web"` |
| `vm_names` | Noms des VM (= noms d'hôte Ansible) | `["fleetinfo-web-1", "fleetinfo-web-2"]` |
| `vm_public_ips` | IP publique par VM | `{ "fleetinfo-web-1" = "203.0.113.21", ... }` |
| `vm_internal_ips` | IP interne par VM | `{ "fleetinfo-web-1" = "10.10.0.2", ... }` |
| `fleetinfo_urls` | URL de la page d'accueil par VM (`:<port>` ajouté si `http_port` n'est pas 80) | `{ "fleetinfo-web-1" = "http://203.0.113.21/", ... }` |
| `health_urls` | URL de `/health` par VM (même règle de port) | `{ "fleetinfo-web-1" = "http://203.0.113.21/health", ... }` |
| `ssh_commands` | Commande SSH par VM, **à lancer depuis la racine du socle** (`socle-web-automatise/`) | `{ "fleetinfo-web-1" = "ssh -i local/ssh/fleet_key ansible@203.0.113.21", ... }` |
| `project_id` | Projet GCP de la session (lu par `prepare-cloud-inventory.sh`) | `"qwiklabs-gcp-00-0123456789ab"` |
| `zone` | Zone des VM | `"us-central1-f"` |

Les modules exposent en plus : `network` → `network_id`, `network_name`, `subnet_id`,
`subnet_name`, `subnet_cidr`, `firewall_rule_names` ; `compute` → `instance_names`, `public_ips`,
`internal_ips`, `self_links`.

### Gestion du state

- **Choix :** state **local** (`terraform/terraform.tfstate`, ignoré par Git), sans bloc
  `backend` (ADR-05). Justification : le projet de lab est éphémère et supprimé en fin de
  session, une seule personne applique à la fois, et un backend distant (bucket GCS) devrait
  lui-même être recréé à chaque session.
- **Précautions :** le state contient en clair l'IP de l'opérateur et le `project_id` ; il ne
  doit jamais être commité ni partagé. Il n'existe que sur le poste qui a lancé `apply` : un
  seul opérateur gère l'infrastructure d'une session (un second poste ne la « verrait » pas et
  tenterait de tout recréer). Toujours lancer `terraform destroy` avant la fin du lab : sinon le
  state local décrit des ressources supprimées avec le projet, et il faut le supprimer avant la
  session suivante (`rm terraform/terraform.tfstate*`).
- **En entreprise :** backend `gcs` dans un bucket dédié (versionnage activé, accès uniforme, IAM
  restreint au compte de service de déploiement, chiffrement CMEK si exigé), verrouillage natif
  du state, un state par environnement, `plan` / `apply` exécutés par une CI avec un compte de
  service (Workload Identity Federation) plutôt que depuis les postes. Exemple de configuration,
  non utilisée ici :

  ```hcl
  terraform {
    backend "gcs" {
      bucket = "novaretail-tfstate"
      prefix = "socle-web-automatise/prod"
    }
  }
  ```

---

## 8. Ansible

### Playbooks

Les deux playbooks sont à la racine de `ansible/`, à côté de `group_vars/` (ADR-09). Ils sont
courts : toute la logique est dans les rôles.

| Playbook | Plays | Usage |
|---|---|---|
| `site.yml` | 1. « Appliquer le socle système commun » (rôle `common`, tag `common`) ; 2. « Configurer le serveur web nginx » (rôle `webserver`, tag `webserver`) ; 3. « Déployer l'application Fleet Info » (rôle `fleetinfo`, tag `fleetinfo`, `serial: [1, "100%"]`, `max_fail_percentage: 0`). Tous sur `hosts: web`, `become: true`. | Point d'entrée unique, identique en local et sur le cloud. |
| `rollback.yml` | « Revenir à une version précédente de Fleet Info » : `include_role` de `fleetinfo` avec `tasks_from: rollback`, même canari. | Retour arrière manuel ([RB-02](docs/runbooks.md#rb-02-revenir-à-une-version-précédente)). |

Un play par couche : les handlers nginx s'exécutent à la fin du play 2, donc **avant** le
déploiement applicatif qui interroge `/health` à travers nginx. `gathering = smart` collecte les
facts une seule fois par hôte et par exécution.

### Rôles

| Rôle | Origine | Responsabilité | Documentation |
|---|---|---|---|
| `common` | Équipe | Vérifie Debian 12 + systemd, paquets de base, fuseau horaire (`community.general.timezone`), compte d'exploitation `fleetops` (groupes `adm` et `systemd-journal`, sans sudo), bannière `/etc/motd`. | [README](ansible/roles/common/README.md) |
| `webserver` | Équipe | `python3-passlib`, compte de `/status` (`community.general.htpasswd`, `no_log`), site `/etc/nginx/sites-enabled/fleetinfo.conf` (validé avant écriture), handlers de validation et de rechargement, enveloppe `nginx.conf.j2` (en-tête de `/etc/nginx/nginx.conf`). Dépend de `geerlingguy.nginx` (`meta/main.yml`). | [README](ansible/roles/webserver/README.md) |
| `fleetinfo` | Équipe (rôle public interdit) | Releases `/opt/fleetinfo/releases/<version>`, bascule du lien `current`, contrôle `/health`, `block` / `rescue` / `always`, journal, fait local, ménage des releases, retour arrière manuel (point d'entrée `rollback`). | [README](ansible/roles/fleetinfo/README.md) |
| `geerlingguy.nginx` 3.3.1 | Ansible Galaxy (licence MIT) | Paquet nginx, `nginx.conf` validé, service ; paramètres imposés par `webserver` : `nginx_remove_default_vhost: true`, `nginx_vhosts: []`, `nginx_server_tokens: "off"`, `nginx_conf_template` (enveloppe avec en-tête). | Justification (maintenance, licence, compatibilité, risques) : ADR-04 dans [docs/decisions.md](docs/decisions.md) et [README du rôle webserver](ansible/roles/webserver/README.md) |

Chaque rôle de l'équipe a l'arborescence standard (`tasks/`, `handlers/`, `templates/`,
`defaults/`, `vars/`, `meta/`), un `meta/main.yml` et un `meta/argument_specs.yml` (types des
variables validés avant la première tâche). Chaque rôle est rejouable seul et idempotent :
au second passage, `--tags common` (ok=9), `--tags webserver` (ok=17) et `--tags fleetinfo`
(ok=22) donnent `changed=0` (vérifié le 2026-11-04).

### Inventaires

| | Local | Cloud |
|---|---|---|
| Fichier | `inventories/local/hosts.yml` (statique ; inventaire par défaut de `ansible.cfg`) | `inventories/cloud/fleet.gcp.yml` (généré ; plugin `google.cloud.gcp_compute`) |
| Hôtes | `node1`, `node2` (résolus par le DNS Docker) | Noms des VM (`fleetinfo-web-1`...), `ansible_host` = IP publique (`natIP`) |
| Groupes | `web` | `web` (label `role`), `env_cloud` (label `env`), `zone_<zone>` (ex. `zone_us_central1_f`) |
| Connexion | `group_vars/all.yml` : `ansible_user: ansible`, clé `/root/.ssh/fleet_key`, `ansible_host_key_checking: false` | `compose` : `ansible_host` (IP publique), `ansible_user` (déduit de la métadonnée `ssh-keys`) ; `group_vars/all.yml` : `ansible_user: ansible` (repli), clé `/root/.ssh/fleet_key`, `-o StrictHostKeyChecking=accept-new` |
| `group_vars/all.yml` (autres) | `socle_env: local` | `socle_env: cloud`, `fleetinfo_cloud_zone`, `fleetinfo_cloud_machine_type`, `fleetinfo_cloud_public_ip` |
| Usage | `ansible-playbook site.yml` | `ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml` |

### Tags

| Tag | Contenu | Exemple d'usage |
|---|---|---|
| `common` | Play 1, rôle `common` | `ansible-playbook site.yml --tags common` |
| `webserver` | Play 2, rôle `webserver` et sa dépendance `geerlingguy.nginx` | Après une modification de configuration nginx ou du mot de passe `/status` |
| `fleetinfo` | Play 3, rôle `fleetinfo` | Livraison d'une version, démonstration d'échec |

### Mécanismes (résumé)

- **Validation et handlers** (`roles/webserver/`) : le template du site est d'abord testé
  **avant écriture** (`validate:` : `nginx -t` sur le fichier candidat dans une configuration
  minimale) ; s'il a changé, il notifie « Valider la configuration nginx » (`nginx -t` complet),
  qui notifie « Recharger nginx » (`state: reloaded`). Une configuration invalide n'est donc
  jamais écrite ni appliquée. Reload et non restart ; le seul restart est celui de
  `geerlingguy.nginx` au premier passage (ADR-10). Vérifié en local : un changement qui ne
  touche que la page (ex. `-e fleetinfo_environment=demo`) ne déclenche aucun handler ; un
  changement du site (`webserver_status_allowed_networks`, ou le port avec
  `-e socle_http_port=8080`) déclenche validation puis reload ; une configuration invalide
  (`webserver_listen_port=99999`) est refusée avant écriture, fichier et site intacts ; un
  second passage ne déclenche aucun handler.
- **block / rescue / always** (`roles/fleetinfo/tasks/deploy.yml`) : génération de la release,
  bascule atomique de `current`, `ansible.builtin.uri` sur `/health` (statut `ok` + version
  attendue) ; en cas d'échec, rebascule vers la release N-1 mémorisée avant la bascule, reload
  nginx, revérification (dans un bloc imbriqué : même si N-1 ne répond pas, le message final
  reste explicite, statut `ECHEC_ROLLBACK_KO`), `fail` explicite ; journal de chaque tentative
  (ADR-08). Détail :
  [docs/architecture.md, section 7](docs/architecture.md#7-cycle-de-vie-dun-déploiement).
- **Déploiement canari** : `serial: [1, "100%"]` et `max_fail_percentage: 0` ; si le premier
  serveur échoue, les autres ne reçoivent jamais la version défectueuse.
- **Ansible Vault** : `group_vars/all/vault.yml` chiffré, variables préfixées `vault_`,
  référencées par `group_vars/all/vars.yml` ; `no_log: true` sur la tâche `htpasswd` et sur
  l'option `webserver_status_password` de l'`argument_specs` ; mot de passe du coffre dans
  `../.vault_pass` (non versionné) (ADR-11).
- **Templates** : chaque fichier généré commence par l'en-tête `ansible_managed` défini dans
  `ansible.cfg` (« Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN ... »),
  sans date ni chemin absolu pour préserver l'idempotence.

| Template | Fichier généré sur le serveur | Forme de l'en-tête |
|---|---|---|
| `roles/common/templates/motd.j2` | `/etc/motd` | Commentaire `#` + ligne `Source :` |
| `roles/webserver/templates/fleetinfo.conf.j2` | `/etc/nginx/sites-enabled/fleetinfo.conf` | Commentaire `#` + ligne `Source :` |
| `roles/fleetinfo/templates/index.html.j2` | `/opt/fleetinfo/releases/<version>/index.html` | Commentaires HTML `<!-- ... -->` |
| `roles/fleetinfo/templates/health.json.j2` | `/opt/fleetinfo/releases/<version>/health.json` | Clés `_ansible_managed` et `_source` |
| `roles/fleetinfo/templates/fleetinfo.fact.j2` | `/etc/ansible/facts.d/fleetinfo.fact` | Clés `_ansible_managed` et `_source` |

- **Page adaptée à l'environnement** : la section « Cloud · Google Compute Engine » (zone, type
  de machine) n'est rendue que si `fleetinfo_cloud_zone` ou `fleetinfo_cloud_machine_type` sont
  renseignées (group_vars cloud) ; en local, ces variables valent `""` et la section est absente,
  sans aucune condition sur l'environnement dans le rôle (ADR-01).
- **Idempotence de la page** : la date du dernier déploiement est mémorisée dans le fait local
  `fleetinfo.fact` (`ansible_local.fleetinfo`) ; la page n'affiche aucune valeur instable (heure
  courante, uptime, espace libre) (ADR-13).
- **Mode simulation** : `--check --diff` passe sans erreur sur un serveur conforme
  (`changed=0`) et annonce les changements d'une nouvelle version sans rien modifier.
- **Qualité** : `ansible-lint` (profil `production`), lancé dans le controller depuis
  `/workspace/ansible` : `Passed: 0 failure(s), 0 warning(s)` (vérifié le 2026-11-03).

### Variables : où les modifier

Référence complète (toutes les variables, où elles sont définies, valeurs par défaut) :
**[docs/variables.md](docs/variables.md)**. Précédence utilisée, de la plus faible à la plus
forte :

```text
roles/<rôle>/defaults/main.yml         valeurs par défaut des rôles (préfixe du rôle)
inventories/<env>/group_vars/all.yml   ce qui diffère entre local et cloud
group_vars/all/vars.yml + vault.yml    valeurs communes du socle et secrets
roles/<rôle>/vars/main.yml             constantes internes (non surchargeables en pratique)
-e (extra-vars)                        surcharge ponctuelle en ligne de commande
```

Règle d'exploitation : ne jamais modifier `defaults/` ni `vars/` d'un rôle pour changer un
comportement ; surcharger dans `ansible/group_vars/all/vars.yml` (les deux environnements) ou
dans `ansible/inventories/<env>/group_vars/all.yml` (un seul environnement, à condition que la
variable ne soit pas aussi dans `group_vars/all/vars.yml`, qui l'emporte).

Variables les plus utilisées en exploitation :

| Variable | Valeur actuelle | Définie dans | Effet |
|---|---|---|---|
| `fleetinfo_version` | `"1.0.0"` | `ansible/group_vars/all/vars.yml` (seul endroit à modifier) | Version de Fleet Info déployée. |
| `socle_http_port` | `80` | `ansible/group_vars/all/vars.yml` | Port nginx et port du contrôle de santé (cohérent avec `http_port` Terraform et les ports Compose). |
| `socle_app_root` | `/opt/fleetinfo` | `ansible/group_vars/all/vars.yml` | Racine de l'application (releases et lien `current`). |
| `socle_env` | `local` / `cloud` | `ansible/inventories/<env>/group_vars/all.yml` | Environnement affiché sur la page, dans `/health` et dans la bannière. |
| `webserver_status_user` | `exploitation` | Défaut de `roles/webserver/defaults/main.yml` ; surcharger dans `group_vars/all/vars.yml` | Compte de `/status`. |
| `webserver_status_password` | secret | `group_vars/all/vars.yml` → `vault_webserver_status_password` (coffre) | Mot de passe de `/status`. |
| `webserver_status_allowed_networks` | `[]` | Défaut de `roles/webserver/defaults/main.yml` ; surcharger dans les `group_vars` | Filtrage IP de `/status` en plus du mot de passe. |
| `fleetinfo_keep_releases` | `3` | Défaut de `roles/fleetinfo/defaults/main.yml` ; surcharger dans `group_vars/all/vars.yml` | Releases conservées (active et précédente toujours protégées). |
| `fleetinfo_simulate_failure` | `false` | `-e` uniquement | Démonstration du retour arrière. |
| `fleetinfo_rollback_version` | `""` (= précédente) | `-e` avec `rollback.yml` | Cible du retour arrière manuel. |
| `common_timezone` | `Europe/Paris` | Défaut de `roles/common/defaults/main.yml` ; surcharger dans `group_vars/all/vars.yml` | Fuseau horaire des serveurs. |

---

## 9. Décisions techniques

Justifications complètes et alternatives écartées : **[docs/decisions.md](docs/decisions.md)**.
La numérotation est figée : le code y renvoie.

| ADR | Décision | En une ligne |
|---|---|---|
| ADR-01 | Un seul code Ansible pour deux environnements | Différences uniquement via l'inventaire et ses `group_vars` ; aucune condition sur l'environnement dans les rôles. |
| ADR-02 | Controller Ansible conteneurisé (local et cloud) | `ansible-core` 2.17 (et non le paquet `ansible` complet) + collections et rôle épinglés, installés dans le projet ; écartés : WSL, venv sur le poste, paquet `ansible` 10. |
| ADR-03 | Image des nœuds locaux | `debian:bookworm-slim` + systemd en PID 1 (`privileged`, `cgroup: host`, tmpfs `/run`) ; écartés : sshd en PID 1 (pas de systemd), images tierces, VM Vagrant. |
| ADR-04 | Rôle public `geerlingguy.nginx` 3.3.1 | Installation de nginx et `nginx.conf` ; site et `/status` dans notre rôle `webserver` ; `fleetinfo` écrit par l'équipe. |
| ADR-05 | State Terraform local | Adapté au lab éphémère ; en entreprise : backend GCS versionné et verrouillé. |
| ADR-06 | Accès SSH | Clé ed25519 locale (jamais commitée) injectée via `ssh-keys`, OS Login désactivé sur les VM, SSH limité à l'IP de l'opérateur en `/32` ; écartés : OS Login, IAP TCP forwarding, clé générée par Terraform (clé privée dans le state). |
| ADR-07 | Inventaire dynamique `google.cloud.gcp_compute` | Filtre `labels.app = fleetinfo` + `RUNNING`, noms d'hôte = noms des VM, `gce_*`, `ansible_host` = `natIP`, groupe `web` par `keyed_groups`, `fleet.gcp.yml` généré depuis un modèle, ADC. |
| ADR-08 | Déploiement par releases | Releases + lien `current` basculé atomiquement, `/health` contrôlé, `block` / `rescue` / `always`, journal, canari, 3 releases conservées. |
| ADR-09 | Plays écrits dans `site.yml` | Pas de dossier `playbooks/` importé, à cause du chargement des `group_vars` de playbook. |
| ADR-10 | Validation nginx avant écriture et par chaîne de handlers | `validate:` du site (fichier candidat) puis `nginx -t` complet et reload ; reload et non restart ; une configuration invalide n'est jamais écrite. |
| ADR-11 | Secrets | Ansible Vault (`vault_`, `no_log`), mot de passe `/status` aléatoire de 24 caractères, `apr_md5_crypt` ; Terraform : `ssh_source_ranges` sensible. |
| ADR-12 | Terraform en modules locaux | Modules `network` et `compute`, `count` pour le nombre de VM, validations de variables (Terraform >= 1.9), versions dans `versions.tf` uniquement. |
| ADR-13 | Idempotence de la page | Date du dernier déploiement mémorisée dans le fait local `fleetinfo.fact`, facts instables exclus. |

---

## 10. Où regarder en cas de problème

Guide complet (journaux, fichiers générés, commandes de diagnostic, erreurs déjà rencontrées et
leur solution, arbre de décision) : **[docs/troubleshooting.md](docs/troubleshooting.md)**.

**Sur un serveur** (VM : `ssh -i /root/.ssh/fleet_key ansible@<IP>` depuis le controller ; nœud
local : `docker compose exec node1 bash` depuis `local/`, shell root, `sudo` inutile). Les
journaux sont lisibles avec `sudo` ; le compte d'exploitation `fleetops` (groupe `adm`) peut
aussi les lire.

| Quoi | Où | Commande |
|---|---|---|
| Journal des déploiements | `/var/log/fleetinfo/deploy.log` (root:adm, 0640) | `sudo tail -n 20 /var/log/fleetinfo/deploy.log` |
| Journaux nginx du site | `/var/log/nginx/fleetinfo.access.log`, `/var/log/nginx/fleetinfo.error.log` | `sudo tail -n 50 /var/log/nginx/fleetinfo.error.log` |
| Service nginx | systemd | `systemctl status nginx` ; `sudo journalctl -u nginx -n 50` ; `sudo nginx -t` |
| Release active | `/opt/fleetinfo/current` → `/opt/fleetinfo/releases/<version>` | `ls -l /opt/fleetinfo/current /opt/fleetinfo/releases/` |
| Fait local (version, précédente, date) | `/etc/ansible/facts.d/fleetinfo.fact` | `cat /etc/ansible/facts.d/fleetinfo.fact` |
| Configuration du site | `/etc/nginx/sites-enabled/fleetinfo.conf` | `head -3 /etc/nginx/sites-enabled/fleetinfo.conf` |
| Compte `/status` | `/etc/nginx/fleetinfo-status.htpasswd` (root:www-data, 0640) | `sudo cat /etc/nginx/fleetinfo-status.htpasswd` (empreinte uniquement) |
| Bannière | `/etc/motd` | `cat /etc/motd` |
| Santé applicative | `/health` | `curl -s http://127.0.0.1/health` |

Valeurs possibles de `resultat=` dans le journal : `SUCCES`, `ECHEC_ROLLBACK_OK` (N-1 restaurée
et vérifiée), `ECHEC_ROLLBACK_KO` (N-1 ne répond pas non plus : incident), `ECHEC_SANS_ROLLBACK`
(aucune N-1 : premier déploiement ou mise à jour sur place). Valeurs de `type=` : `deploiement`,
`mise-a-jour-sur-place`, `rollback-manuel`.

**Depuis le controller** (`/workspace/ansible`, ajouter `-i inventories/cloud/fleet.gcp.yml` pour
le cloud) :

| Besoin | Commande |
|---|---|
| Hôtes et groupes vus par Ansible | `ansible-inventory --graph` ; variables d'hôte : `ansible-inventory --list` |
| Connectivité SSH | `ansible web -m ansible.builtin.ping` |
| Version active et précédente sur tous les serveurs | `ansible web -m ansible.builtin.setup -a 'filter=ansible_local'` |
| Écarts par rapport au code | `ansible-playbook site.yml --check --diff` |
| Exécution détaillée | `ansible-playbook site.yml -vvv` |
| Lint | `ansible-lint` |

**Depuis le poste** : `docker compose ps` et `docker compose logs <service>` (dans `local/`) ;
`terraform -chdir=terraform output`, `terraform -chdir=terraform state list`,
`gcloud compute instances list`.

Erreurs les plus fréquentes (toutes détaillées dans le guide,
[section 4](docs/troubleshooting.md#4-erreurs-déjà-rencontrées-et-leur-solution)) :

| Symptôme | Cause et solution |
|---|---|
| `Mot de passe Vault introuvable : créer socle-web-automatise/.vault_pass ...` (controller) ou `The vault password file ... was not found` | Créer `.vault_pass` à la racine du socle ([section 4](#mot-de-passe-ansible-vault)). |
| `Permission non accordée` sur `generate-keys.sh` | Bit exécutable perdu : `bash local/scripts/generate-keys.sh`. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` (cloud) | IP éphémère réutilisée par une nouvelle VM : `ssh-keygen -R <IP>` dans le controller. |
| Inventaire cloud vide | `project_id` de `fleet.gcp.yml` (relancer `prepare-cloud-inventory.sh`), label `app`, VM non `RUNNING`, ADC absentes. |
| `DefaultCredentialsError` | `gcloud auth application-default login` sur le poste, puis `./scripts/prepare-cloud-inventory.sh`. |
| Timeout SSH vers les VM | IP publique du poste changée : mettre à jour `ssh_source_ranges`, puis `terraform apply`. |
| `nginx -t` en échec, handler « Recharger nginx » non exécuté | Configuration invalide : corriger la variable, rejouer `--tags webserver` (le site est resté en ligne avec l'ancienne configuration). |
| Build ou démarrage du banc en échec, disque presque plein | Images d'environ 1 Go : `docker builder prune` puis `docker image prune`. |

---

## 11. Limites connues et dette technique

| Limite | Impact | Ce que nous ferions ensuite |
|---|---|---|
| **Cloud pas encore validé de bout en bout** sur un vrai projet GCP (session de lab expirée) | Les résultats cloud de ce README sont attendus, non observés | Répétition générale dans une session neuve, en suivant uniquement ce README ; corriger les écarts. |
| Durée du lab non relevée ; durée de reconstruction complète non mesurée | Marge de temps inconnue | Relever les deux à la prochaine session ([docs/lab-gcp.md](docs/lab-gcp.md)). |
| State Terraform local, sur un seul poste | Pas de travail à plusieurs sur la même infrastructure ; state perdu = ressources orphelines jusqu'à la fin du lab | Backend GCS versionné et verrouillé (section 7, ADR-05). |
| Pas de CI | `terraform fmt` / `validate` et `ansible-lint` lancés à la main | Pipeline sur chaque Pull Request : fmt, validate, lint, `--check` sur le banc local. |
| `ansible-core` 2.17 en fin de vie | Plus de correctifs de sécurité | Monter vers 2.18+ et réaligner les collections (`requirements.yml`, `requirements.txt`), retester le banc. |
| HTTP seulement, pas de TLS | Le mot de passe de `/status` (HTTP Basic) circule en clair sur Internet | TLS (certificat géré, load balancer HTTPS) ; en attendant, restreindre `/status` avec `webserver_status_allowed_networks`. |
| IP publiques éphémères, pas de load balancer ni de DNS | Les URL changent à chaque recréation (ou arrêt / démarrage) d'une VM ; pas de point d'entrée unique | IP statiques ou load balancer HTTP(S) + enregistrement DNS. |
| Bascule avant contrôle de santé, sans retrait du trafic | Pendant le contrôle `/health` (une dizaine de secondes au plus), le canari sert la nouvelle release, même défectueuse | Load balancer avec retrait du serveur pendant le déploiement, ou contrôle de la release avant bascule. |
| Une seule zone | Pas de tolérance à la panne d'une zone | Répartir les VM sur plusieurs zones (le groupe `zone_<zone>` existe déjà). |
| SSH lié à l'IP publique de l'opérateur | Changement de réseau = timeout SSH | IAP TCP forwarding ou bastion (ADR-06). |
| Premier déploiement en échec | Aucune version vers laquelle revenir (`ECHEC_SANS_ROLLBACK`) | Déployer d'abord une version connue saine (`1.0.0`). |
| Validation unitaire du site nginx | Le `validate:` teste le fichier de site seul dans une configuration minimale : un conflit avec un autre fichier inclus n'est vu que par le handler (le fichier est alors déjà écrit) | Sans objet tant que le socle n'a qu'un site ; sinon, valider la configuration complète avec le candidat avant écriture (ADR-10). |
| Page Fleet Info publique | Le FQDN affiché sur GCE (`<vm>.<zone>.c.<project_id>.internal`) révèle le `project_id` du lab à quiconque consulte la page | Masquer le FQDN en cloud, ou restreindre `http_source_ranges`. |
| `--check` sur un serveur vierge | Échoue (paquets et utilisateurs absents) | Comportement normal ; utiliser `--check` uniquement sur des serveurs déjà déployés. |
| `rollback.yml` | Fait l'aller-retour entre les deux dernières releases ; la page restaurée garde la date de son déploiement initial | Afficher la date de bascule séparément de la date de génération. |
| Pas de supervision ni d'alerting | Une panne n'est vue qu'en consultant la page | Sonde sur `/health` (Cloud Monitoring uptime check) et alertes. |
| ADC de l'utilisateur copiées dans `.secrets/` | Identifiants personnels sur disque, avec tous les droits de l'utilisateur | Compte de service dédié en lecture seule (`roles/compute.viewer`) pour l'inventaire. |
| Même clé SSH pour le local et le cloud | Une fuite de la clé du banc local ouvre aussi les VM | Clés distinctes par environnement, rotation documentée. |
| Mises à jour de l'OS non gérées | Paquets installés en `state: present`, jamais mis à jour | `unattended-upgrades` dans le rôle `common`, ou fenêtre de mise à jour planifiée. |
| Windows : parades non rejouées sur un poste Windows | ADC sous `%APPDATA%`, `.vault_pass` lu par script, clé SSH recopiée (section 5.3) : écarts possibles | Rejouer sur un poste Windows ; privilégier WSL 2. |

---

## 12. Définition de terminé

Checklist du §10 des consignes. « Vérifié » = constaté sur le banc local (2026-11-03, puis
2026-11-04 après les dernières corrections) ; « À valider » = à constater en cloud lors de la
répétition générale.

| Critère | État | Preuve / comment vérifier |
|---|---|---|
| Une session de lab neuve + le README suffisent à tout redéployer, sans aide orale | Local : procédure de la section 5.1 vérifiée sur le banc le 2026-11-03 ; déroulé « README seul » par un membre qui ne l'a pas écrit **à faire**. Cloud : **à valider** | Répétition générale : un membre suit uniquement la section 5 (local puis cloud), dans une session de lab neuve. |
| `terraform plan` après `apply` → `No changes` | **À valider** (hors ligne : `fmt`, `validate` et `plan` → `Plan: 6 to add`, 7 avec `vm_count = 3`, vérifiés ; validations testées) | Étape C4. |
| Second `ansible-playbook site.yml` → `changed=0`, en local et sur le cloud | Local : vérifié (nœuds neufs : `ok=45 changed=23`, puis `ok=40 changed=0` par nœud ; `--check --diff` : `changed=0`). Cloud : **à valider** | Étapes L8 et C9. |
| Le même `site.yml` et les mêmes rôles servent dans les deux environnements | Vérifié par construction ; rendu de la page avec les `group_vars` cloud vérifié en simulation. Exécution cloud **à valider** | Un seul `site.yml` ; seuls `inventories/*/group_vars/all.yml` diffèrent. |
| Ajouter une VM côté Terraform ne demande aucune modification du code Ansible | Vérifié par construction (sélection par labels, plugin testé sur une réponse simulée de l'API). **À valider** en cloud | [RB-03](docs/runbooks.md#rb-03-ajouter-ou-retirer-un-serveur) : `vm_count = 3`, `terraform apply`, `site.yml`. |
| Un déploiement en échec revient automatiquement à la version précédente, site toujours en ligne | Vérifié en local. Cloud : **à valider** | [Section 6](#6-runbooks-dexploitation) : `failed=1 rescued=1`, site en N-1, `ECHEC_ROLLBACK_OK` dans le journal. |
| Les fichiers générés sur les serveurs sont identifiables comme gérés par Ansible | Vérifié | `fleetinfo.conf`, `/etc/nginx/nginx.conf` (enveloppe du template public), `index.html`, `health.json`, `/etc/motd`, `fleetinfo.fact` ([section 8](#8-ansible)). Seul le fichier `htpasswd`, produit par un module, n'a pas d'en-tête. |
| Aucun secret en clair dans le dépôt ni dans son historique | Vérifié le 2026-11-03 : recherche du mot de passe `/status` sans résultat hors `vault.yml` chiffré ; chaque version commitée de `vault.yml` commence par `$ANSIBLE_VAULT;1.1;AES256` ; aucun `.vault_pass`, state, `tfvars`, clé, ADC ni `fleet.gcp.yml` dans l'historique. **À refaire** après le commit des travaux en cours | `git log --all --name-only --format= \| sort -u` ; `git grep` sur le mot de passe ; `git show <commit>:<chemin>/vault.yml \| head -1`. |
| `terraform fmt -check`, `terraform validate` et `ansible-lint` passent | Vérifié (dernier passage le 2026-11-04 : Terraform 1.17.1 ; `ansible-lint` 25.9.2, profil `production`, 0 failure, 0 warning) | Sections [7](#7-terraform) et [8](#8-ansible). |
| Chaque rôle a son README, chaque variable est documentée, chaque rôle public est justifié | Rédigé le 2026-11-03 (README des rôles, [docs/variables.md](docs/variables.md), ADR-04) ; **relecture croisée à faire** | Liens de la [section 8](#8-ansible). |
| Chaque membre de l'équipe sait expliquer et exécuter chaque runbook | **À faire** : point d'équipe et passage de chaque runbook par chaque membre avant la soutenance | [docs/runbooks.md](docs/runbooks.md). |

---

## 13. Organisation de l'équipe et Git

L'organisation du dépôt, les membres de l'équipe et les règles Git sont décrits dans le
[README racine du dépôt](../../README.md). En résumé :

- **Trunk-based development** : `main` est l'unique branche de référence et doit toujours
  fonctionner ; pas de branche `develop` ni de branche de release.
- **Branches courtes** créées depuis `main` et fusionnées en moins de deux jours, nommées
  `<type>/<projet>-<description>` en minuscules et sans accent (ex. `feat/p1-terraform-network`,
  `docs/p1-runbook-rollback`).
- **Pull Request obligatoire** : pas de push direct sur `main`, une relecture approuvée par un
  autre membre, branche à jour avec `main`, fusion en *Squash and merge*, branche supprimée
  ensuite.
- Messages de commit au format `type(portée): description`, la portée étant facultative
  (`feat`, `fix`, `docs`, `refactor`, `chore`).
- Recommandé avant chaque Pull Request touchant le socle (en l'absence de CI) :
  `terraform fmt -check -recursive`, `terraform validate`, `ansible-lint` et un second
  `ansible-playbook site.yml` à `changed=0` sur le banc local.
- La documentation est l'affaire de tous : chaque membre documente ce qu'il produit (README de
  rôle, runbook, ADR), le tech lead assure la cohérence avec ce README.
