# Environnement cloud : contraintes du lab Google Skills

Ce document décrit l'environnement GCP dans lequel le socle est déployé : un **projet
temporaire** fourni par un lab Google Skills, recréé à chaque session. Il indique ce qui est
connu, ce qui reste à relever, et comment reconstruire l'environnement de zéro en début de
session.

- [1. Les labs utilisés](#1-les-labs-utilisés)
- [2. Synthèse des contraintes](#2-synthèse-des-contraintes)
- [3. Durée limitée et budget-temps](#3-durée-limitée-et-budget-temps)
- [4. Identifiants changeants](#4-identifiants-changeants)
- [5. Région, zone et types de machine](#5-région-zone-et-types-de-machine)
- [6. API et politiques du projet](#6-api-et-politiques-du-projet)
- [7. Connexion avec le compte étudiant](#7-connexion-avec-le-compte-étudiant)
- [8. Poste de contrôle : pas de Cloud Shell](#8-poste-de-contrôle--pas-de-cloud-shell)
- [9. Reconstruire de zéro à chaque session](#9-reconstruire-de-zéro-à-chaque-session)
- [10. Fin de session](#10-fin-de-session)
- [11. À relever lors de la première session](#11-à-relever-lors-de-la-première-session)

Documents liés : [README du socle](../README.md) (section 5.2, déploiement cloud pas à pas),
[script de démonstration](demo.md), [runbooks](runbooks.md), [dépannage](troubleshooting.md),
[décisions techniques](decisions.md).

> **Statut** : le déploiement cloud n'a pas encore été exécuté de bout en bout sur un vrai
> projet GCP (session de lab expirée). Toutes les sorties cloud de ce document sont des
> **résultats attendus**. Les informations issues d'une session précédente sont signalées
> comme telles. Ne jamais écrire dans ce dépôt un `project_id`, un compte ou un mot de passe
> réels : les exemples utilisent `qwiklabs-gcp-00-0123456789ab` et `203.0.113.10`.

---

## 1. Les labs utilisés

Le projet GCP est fourni par l'un des deux labs cités au §2.5 des [consignes](../../README.md) :

| Lab | URL |
|---|---|
| Lab 576066 | https://www.skills.google/paths/11/course_templates/443/labs/576066 |
| Lab 508950 | https://www.skills.google/paths/11/course_templates/443/labs/508950 |

- Les deux pages ne sont accessibles **qu'après connexion** à Google Skills (redirection vers
  la page de connexion constatée le 2026-11-03) : leur durée, leurs instructions et leurs
  restrictions n'ont pas pu être relevées hors session.
- Le socle ne dépend d'aucun contenu propre à l'un ou l'autre lab : il n'utilise que le projet
  GCP temporaire, le compte étudiant et l'API Compute Engine. N'importe lequel des deux
  convient, sous réserve des relevés de la [section 11](#11-à-relever-lors-de-la-première-session).

---

## 2. Synthèse des contraintes

| Contrainte | Ce que cela implique | Réponse du socle |
|---|---|---|
| **Durée limitée** : le projet et tout son contenu sont supprimés en fin de session | Le déploiement complet doit tenir largement dans la durée du lab | Reconstruction en quelques commandes ([section 9](#9-reconstruire-de-zéro-à-chaque-session)) ; budget-temps estimé ([section 3](#3-durée-limitée-et-budget-temps)) ; state Terraform local (ADR-05). |
| **Identifiants changeants** : `project_id`, compte étudiant, mot de passe temporaire | Rien de propre à une session ne doit être écrit dans le code | `project_id` en variable Terraform (`terraform.tfvars`, non versionné) ; inventaire Ansible généré (`fleet.gcp.yml`, non versionné) ; ADC copiées dans `.secrets/` (non versionné). |
| **Périmètre restreint** : région, zone, types de machine, API éventuellement limités | Les valeurs doivent pouvoir changer sans toucher au code | `region`, `zone`, `machine_type`, `vm_count` en variables ; validation zone/région au `plan` ([section 5](#5-région-zone-et-types-de-machine)). |
| **Poste de contrôle local** | Terraform et `gcloud` tournent sur le poste ; Ansible dans le controller Docker du poste | ADR-02 ; aucun outil à installer dans le projet du lab. |
| **Cloud Shell interdit pour le développement** | Le travail fait dans Cloud Shell disparaît avec le lab | Tout le code est dans le dépôt Git ; Cloud Shell n'est jamais nécessaire ([section 8](#8-poste-de-contrôle--pas-de-cloud-shell)). |
| **Comptes et droits imposés par le lab** | Pas de compte de service ni de rôle IAM à créer ; OS Login éventuellement actif | ADC de l'utilisateur (`auth_kind: application`) ; clé SSH par métadonnée et `enable-oslogin = "FALSE"` (ADR-06, ADR-07). |

---

## 3. Durée limitée et budget-temps

**Durée relevée : à compléter lors de la première session** (minuteur affiché dans le panneau
du lab ; reporter aussi la valeur dans la section « Contraintes du lab GCP » du
[README](../README.md)).

Budget-temps **estimé** d'une reconstruction complète, à chronométrer lors de la répétition
générale. Hypothèse : le poste est déjà préparé (clé SSH, `.vault_pass`, images Docker
construites, dépendances Galaxy installées : étapes L1 à L5 du README, réalisées avant la
session).

| N° | Étape | Où | Durée estimée | Durée mesurée |
|---|---|---|---|---|
| 1 | Démarrer le lab, attendre la mise à disposition du projet, relever `project_id`, compte, durée | navigateur | 3 à 5 min | à compléter |
| 2 | Ouvrir la console en navigation privée avec le compte du lab | navigateur | 1 à 2 min | à compléter |
| 3 | `gcloud auth login`, `gcloud config set project`, `gcloud auth application-default login` | poste | 2 à 3 min | à compléter |
| 4 | Contrôles : API Compute Engine, zones disponibles, IP publique du poste | poste | 1 min | à compléter |
| 5 | Renseigner `terraform/terraform.tfvars` | poste | 1 à 2 min | à compléter |
| 6 | `terraform init` puis `terraform plan` | poste | 1 à 2 min | à compléter |
| 7 | `terraform apply` (6 ressources) puis `terraform plan` (`No changes`) | poste | 2 à 3 min | à compléter |
| 8 | `./scripts/prepare-cloud-inventory.sh` | poste | moins d'1 min | à compléter |
| 9 | `docker compose up -d --wait` puis shell du controller | poste | moins d'1 min | à compléter |
| 10 | Attente de l'agent invité, `ansible-inventory --graph`, `ansible ... -m ansible.builtin.ping` | controller | 1 à 2 min | à compléter |
| 11 | Premier `ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml` (2 VM, canari) | controller | 3 à 6 min | à compléter |
| 12 | Second passage (`changed=0`) | controller | 1 à 2 min | à compléter |
| 13 | Vérifications : URL, `/health`, SSH, `/status` | poste | 2 min | à compléter |
| | **Sous-total : environnement opérationnel** | | **environ 20 à 30 min** | à compléter |
| 14 | Démonstration (scénario du §8 des consignes, durées cibles de [demo.md](demo.md)) | | environ 15 min | à compléter |
| 15 | `terraform -chdir=terraform destroy` et nettoyage ([section 10](#10-fin-de-session)) | poste | 1 à 3 min | à compléter |
| | **Total estimé (étapes 1 à 15)** | | **environ 35 à 50 min** | à compléter |

Règles d'usage :

- Le déploiement doit tenir **largement** dans la durée du lab : viser un total (déploiement,
  démonstration et destruction) **inférieur à la moitié** de la durée relevée. Si ce n'est pas
  le cas, préparer davantage avant la session (images, inventaire généré en passant le projet
  en argument, voir [demo.md](demo.md)).
- Si le poste n'a jamais construit les images Docker, compter en plus le téléchargement des
  images de base et l'installation des dépendances Python (plusieurs minutes, selon le
  réseau) : à faire **avant** de démarrer le lab.
- Vérifier le temps restant dans le panneau avant toute opération longue, et toujours garder
  le temps d'un `terraform destroy`.

---

## 4. Identifiants changeants

À chaque session, le lab fournit un nouveau projet et un nouveau compte. Aucun de ces
identifiants n'est écrit dans un fichier versionné.

| Identifiant | Forme (exemple fictif) | Où il est utilisé | Fichier versionné ? |
|---|---|---|---|
| `project_id` | `qwiklabs-gcp-00-0123456789ab` | `terraform/terraform.tfvars` (`project_id`), `gcloud config`, `ansible/inventories/cloud/fleet.gcp.yml` (généré) | Non (`.gitignore`) |
| Compte étudiant | `student-XX-…@qwiklabs.net` | Console GCP (navigation privée), `gcloud auth login`, ADC | Non |
| Mot de passe temporaire du compte | affiché dans le panneau du lab | Connexion à la console et à `gcloud` uniquement | Jamais écrit nulle part |
| ADC (jeton d'accès de l'utilisateur) | `~/.config/gcloud/application_default_credentials.json` | Provider Terraform ; copie `.secrets/gcp-adc.json` pour le plugin d'inventaire | Non (`.secrets/` ignoré) |
| IP publique du poste | `203.0.113.10/32` | `ssh_source_ranges` (`terraform.tfvars`, variable `sensitive`) | Non |
| IP publiques des VM | éphémères, nouvelles à chaque création | Lues dynamiquement (inventaire, `terraform output`) | Non (aucune IP écrite) |

Conséquences pratiques :

- `terraform.tfvars` doit être mis à jour à chaque session (`project_id`, éventuellement
  `region`, `zone`, `ssh_source_ranges`).
- `./scripts/prepare-cloud-inventory.sh` doit être relancé à chaque session (nouveau
  `project_id`, nouvelles ADC).
- Le `known_hosts` du controller contient les clés d'hôte des VM des sessions passées : le
  vider en début de session (erreur n° 8a du [dépannage](troubleshooting.md)).

---

## 5. Région, zone et types de machine

**Région et zone**

- Observées lors d'une session précédente : région **`us-central1`**, zone
  **`us-central1-f`**. Ce sont les valeurs de
  [`terraform.tfvars.example`](../terraform/terraform.tfvars.example).
- Ce sont des variables **sans valeur par défaut** (`region`, `zone` dans
  [`terraform/variables.tf`](../terraform/variables.tf)) : si le lab impose une autre région,
  seul `terraform.tfvars` change. La validation refuse au `plan` une zone hors de la région
  (`La zone doit appartenir à la région choisie ...`).
- Côté Ansible, rien à modifier : le groupe `zone_<zone>` de l'inventaire dynamique suit la
  zone réelle (par exemple `zone_us_central1_f`), et la page affiche la zone lue dans l'API.

Vérification (poste, résultat attendu : la liste des zones de la région, dont la zone choisie
en `UP`) :

```bash
gcloud compute zones list --filter="name~^us-central1"
```

**Types de machine**

| Type | Caractéristiques | Usage |
|---|---|---|
| `e2-small` | 2 vCPU partagés, 2 Go de mémoire | **Défaut du socle** (`machine_type`), suffisant pour nginx et une page statique. |
| `e2-medium` | 2 vCPU partagés, 4 Go de mémoire | Déjà utilisé dans les labs du cours : solution de repli si `e2-small` est refusé. |

Changer de type : `machine_type = "e2-medium"` dans `terraform.tfvars`, puis
`terraform apply`. Sur des VM existantes, Terraform les arrête puis les redémarre
(`allow_stopping_for_update = true`) : l'IP publique éphémère peut changer. L'inventaire
dynamique la relit automatiquement ; relire les URL avec
`terraform -chdir=terraform output fleetinfo_urls` (et, si cette IP a déjà servi à une autre
VM, voir l'erreur n° 8a du [dépannage](troubleshooting.md)).

Les types effectivement autorisés par le lab ne sont pas connus à l'avance : une restriction
se manifesterait par un refus de l'API au `terraform apply` (message à relever,
[section 11](#11-à-relever-lors-de-la-première-session)). La commande suivante liste les types
existants dans la zone, **pas** ceux autorisés par le lab :

```bash
gcloud compute machine-types list --zones=us-central1-f --filter="name~^e2-"
```

**Volumétrie** : 2 VM `e2-small` (4 vCPU partagés, 2 IP externes éphémères) par défaut ;
passer à `vm_count = 3` ajoute 2 vCPU et une IP. Vérifier les quotas régionaux
([section 11](#11-à-relever-lors-de-la-première-session)) avant d'augmenter `vm_count`.

---

## 6. API et politiques du projet

**API nécessaires** : seule l'API **Compute Engine** (`compute.googleapis.com`) est utilisée,
par Terraform (VPC, sous-réseau, firewall, VM) et par le plugin d'inventaire
`google.cloud.gcp_compute`. Le socle n'utilise ni IAP, ni OS Login, ni Secret Manager, ni
bucket GCS.

```bash
# (poste) résultat attendu : une ligne compute.googleapis.com
gcloud services list --enabled --filter="name:compute.googleapis.com"
# si elle est absente (activation pouvant prendre une à deux minutes) :
gcloud services enable compute.googleapis.com
```

Si l'API est désactivée, Terraform échoue (`Error 403 ... accessNotConfigured`) et
l'inventaire reste vide avec l'avertissement
`gcp_compute: skipping project '<PROJECT_ID>' (Compute Engine API is disabled).` (erreur n° 14
du [dépannage](troubleshooting.md)).

**Politiques susceptibles de bloquer le socle** (à vérifier à la première session, si le
compte du lab a le droit de les lire) :

| Politique | Effet sur le socle | Vérification |
|---|---|---|
| OS Login imposé (`constraints/compute.requireOsLogin`) | La métadonnée `ssh-keys` est ignorée : Ansible ne peut plus se connecter (`Permission denied (publickey)`). Il faudrait basculer sur OS Login (ADR-06). | `gcloud resource-manager org-policies describe compute.requireOsLogin --project=<PROJECT_ID> --effective` |
| OS Login activé au niveau du projet (métadonnée) | Sans effet : `enable-oslogin = "FALSE"` posé sur chaque VM l'emporte. | `gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"` |
| IP externes interdites (`constraints/compute.vmExternalIpAccess`) | `terraform apply` refusé (les VM ont une IP publique éphémère, `access_config {}`) ; le socle suppose un accès direct depuis le poste. | `gcloud resource-manager org-policies describe compute.vmExternalIpAccess --project=<PROJECT_ID> --effective` |
| Localisation restreinte (`constraints/gcp.resourceLocations`) | Région ou zone refusée à l'`apply` : changer `region` / `zone` dans `terraform.tfvars`. | `gcloud resource-manager org-policies describe gcp.resourceLocations --project=<PROJECT_ID> --effective` |

---

## 7. Connexion avec le compte étudiant

**Console (navigateur)**

1. Démarrer le lab sur Google Skills et attendre que le panneau affiche les informations de
   la session (compte, mot de passe temporaire, `project_id`, temps restant).
2. Ouvrir la console GCP dans une **fenêtre de navigation privée** (copier le lien proposé par
   le lab), pour ne pas mélanger le compte étudiant avec un compte Google personnel déjà
   connecté.
3. Se connecter avec le compte `student-XX-…@qwiklabs.net` et le mot de passe temporaire du
   panneau ; accepter les conditions demandées. Ne pas activer d'essai gratuit ni de moyen de
   récupération : le compte disparaît avec la session.
4. Vérifier en haut de la console que le projet sélectionné est bien celui du lab.

**`gcloud` sur le poste**

Deux authentifications distinctes, **toutes deux avec le compte du lab** :

| Commande | À quoi elle sert |
|---|---|
| `gcloud auth login` | Identifiants de la CLI `gcloud` (commandes de vérification de ce document). |
| `gcloud auth application-default login` | Application Default Credentials (ADC), utilisées par le provider Terraform et, après copie par `prepare-cloud-inventory.sh`, par le plugin d'inventaire dans le controller. |

```bash
# (poste) remplacer <PROJECT_ID> par l'identifiant du panneau du lab (forme : qwiklabs-gcp-00-0123456789ab)
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud auth application-default login
gcloud config get-value project          # attendu : le project_id de la session
gcloud auth list                         # attendu : le compte du lab marqué *
```

Conseils :

- Les deux commandes ouvrent le navigateur par défaut, où un compte personnel est peut-être
  connecté : choisir explicitement le compte du lab, ou ajouter `--no-launch-browser` pour
  obtenir une URL à coller dans la fenêtre de navigation privée.
- `gcloud auth application-default login` **remplace** les ADC existantes du poste. Pour isoler
  la configuration `gcloud` (compte et projet) du lab, une configuration nommée peut être
  créée : `gcloud config configurations create fleetinfo-lab` (elle devient active), puis
  `gcloud config configurations activate default` en fin de session. Les ADC, elles, restent
  globales.
- Aucun compte de service ni clé JSON n'est nécessaire (ADR-07).

---

## 8. Poste de contrôle : pas de Cloud Shell

- Les consignes interdisent de développer dans **Cloud Shell** : son contenu disparaît avec le
  projet du lab, et le travail non poussé serait perdu.
- Le socle n'en a pas besoin : Terraform et `gcloud` tournent sur le **poste**, Ansible dans
  le **controller** Docker du poste (ADR-02), et tout le code vit dans le dépôt Git.
- La console GCP sert uniquement à **vérifier** (VM, règles de firewall, labels) ; aucune
  ressource n'y est créée ni modifiée à la main : toute modification passe par
  `terraform.tfvars` et `terraform apply`, sinon le `terraform plan` suivant ne serait plus
  `No changes`.

---

## 9. Reconstruire de zéro à chaque session

Principe : une session de lab neuve ne contient **rien**. L'environnement est reconstruit
entièrement avec les commandes ci-dessous ; le détail de chaque étape et de ses résultats
attendus est dans la section 5.2 du [README](../README.md) (étapes C1 à C11).

### 9.1 Avant la session (une fois par poste)

Étapes L1 à L5 du README, à faire hors du temps de lab :

```bash
# (poste, depuis Project-1/socle-web-automatise/)
./local/scripts/generate-keys.sh
printf '%s' 'MOT_DE_PASSE_VAULT_TRANSMIS_PAR_L_EQUIPE' > .vault_pass && chmod 600 .vault_pass
cd local && docker compose up -d --build --wait
docker compose exec controller bash
# (controller : dépendances Galaxy déjà installées par l'entrypoint ; vérification)
ansible-galaxy install -r requirements.yml
```

Résultat attendu : clé `local/ssh/fleet_key.pub` présente, conteneurs `node1` et `node2`
`(healthy)`, `geerlingguy.nginx` 3.3.1, `google.cloud` 1.15.0 et `community.general` 12.6.7
installés dans `ansible/`.

### 9.2 Nettoyer les restes d'une session précédente

Uniquement si la session précédente s'est terminée **sans** `terraform destroy` (lab expiré)
et que son projet n'existe donc plus :

```bash
# (poste, depuis socle-web-automatise/)
rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
rm -f ansible/inventories/cloud/fleet.gcp.yml
rm -rf .secrets
# (controller) clés d'hôte des anciennes VM
rm -f /root/.ssh/known_hosts
```

Ne **jamais** supprimer le state d'une infrastructure encore existante : Terraform perdrait la
trace des ressources (voir ADR-05 et l'erreur n° 13 du [dépannage](troubleshooting.md)).

### 9.3 Commandes minimales de la session

```bash
# (poste, depuis Project-1/socle-web-automatise/) 1. Authentification avec le compte du lab
gcloud auth login
gcloud config set project <PROJECT_ID>          # identifiant du panneau du lab
gcloud auth application-default login

# (poste) 2. Variables de la session
cd terraform
[ -f terraform.tfvars ] || cp terraform.tfvars.example terraform.tfvars   # ne jamais écraser un fichier existant
curl -4 -s https://ifconfig.me ; echo                             # IP publique du poste, à mettre en /32
#   éditer terraform.tfvars : project_id, region, zone, vm_count, ssh_source_ranges

# (poste) 3. Infrastructure
terraform init && terraform plan && terraform apply && terraform plan   # dernier plan : No changes

# (poste) 4. Inventaire dynamique et identifiants du controller
cd .. && ./scripts/prepare-cloud-inventory.sh

# (poste) 5. Controller
cd local && docker compose up -d --wait && docker compose exec controller bash

# (controller) 6. Configuration et déploiement
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph       # @web, @env_cloud, @zone_<zone>
ansible -i inventories/cloud/fleet.gcp.yml web -m ansible.builtin.ping
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml       # changed=0

# (poste) 7. Vérification : après exit du controller, le shell du poste est resté dans local/
cd ..
terraform -chdir=terraform output fleetinfo_urls
```

Résultats attendus (non encore observés) :

- premier `plan` : `Plan: 6 to add, 0 to change, 0 to destroy.`, avec
  `source_ranges = (sensitive value)` sur la règle SSH ;
- `apply` : `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.` ; second `plan` :
  `No changes. Your infrastructure matches the configuration.` ;
- script : `Inventaire généré : ansible/inventories/cloud/fleet.gcp.yml (projet qwiklabs-gcp-00-0123456789ab)`
  puis `Identifiants copiés : .secrets/gcp-adc.json (lus par le controller)` ;
- `--graph` : `fleetinfo-web-1` et `fleetinfo-web-2` dans `@web`, `@env_cloud` et
  `@zone_us_central1_f` (pour la zone `us-central1-f`) ;
- `ping` : `SUCCESS` sur chaque VM (attendre environ une minute après l'`apply`, le temps que
  l'agent invité crée l'utilisateur `ansible`) ;
- premier `site.yml` : `failed=0`, canari `fleetinfo-web-1` puis les autres ; second passage :
  `changed=0` sur toutes les VM ;
- `fleetinfo_urls` : une URL `http://<IP>/` par VM ; la page affiche la section
  « Cloud · Google Compute Engine » (zone, type de machine).

Si une étape échoue : [dépannage](troubleshooting.md), erreurs n° 8 et 12 à 15 en particulier.

---

## 10. Fin de session

À faire **avant** la fin du minuteur (ou avant de cliquer sur la fin du lab dans le panneau) :

```bash
# (poste, depuis socle-web-automatise/)
terraform -chdir=terraform destroy                 # attendu : Destroy complete! Resources: 6 destroyed.
rm -f ansible/inventories/cloud/fleet.gcp.yml
rm -rf .secrets
```

Facultatif, pour ne pas laisser d'identifiants de lab sur le poste :

```bash
gcloud auth application-default revoke
gcloud auth revoke student-XX-...@qwiklabs.net     # remplacer par le compte de la session
```

Si le lab se termine avant le `destroy`, les ressources sont supprimées avec le projet, mais
le state local devient obsolète : appliquer la [section 9.2](#92-nettoyer-les-restes-dune-session-précédente)
au début de la session suivante. Procédure complète de destruction :
[RB-07](runbooks.md#rb-07-détruire-lenvironnement-proprement).

---

## 11. À relever lors de la première session

Tableau à compléter **dans ce fichier** lors de la première session (puis à mettre à jour si
une session diffère), **sans** aucun identifiant réel : noter des formes et des constats, pas
des valeurs de session.

| Élément | Comment le relever | Valeur relevée |
|---|---|---|
| Date de la session et lab utilisé (576066 ou 508950) | Page du lab | à compléter |
| **Durée affichée** | Minuteur du panneau du lab | à compléter |
| Forme du `project_id` | Panneau du lab, `gcloud config get-value project` | à compléter (session précédente : `qwiklabs-gcp-…`) |
| Forme du compte étudiant | Panneau du lab | à compléter (session précédente : `student-XX-…@qwiklabs.net`) |
| Région(s) imposée(s) ou autorisée(s) | Instructions du lab ; `gcloud compute regions list` | à compléter (session précédente : `us-central1`) |
| Zone(s) | `gcloud compute zones list --filter="name~^us-central1"` | à compléter (session précédente : `us-central1-f`) |
| Types de machine acceptés (`e2-small`, `e2-medium`) et type de disque (`pd-balanced`, 10 Go, valeurs par défaut de `boot_disk_type` / `boot_disk_size_gb`) | Instructions du lab ; résultat du `terraform apply` | à compléter |
| Message d'erreur en cas de type, région ou ressource refusés | Sortie de `terraform apply` | à compléter |
| API Compute Engine active à l'ouverture | `gcloud services list --enabled --filter="name:compute.googleapis.com"` | à compléter |
| OS Login au niveau du projet | `gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"` | à compléter |
| Politiques d'organisation (OS Login imposé, IP externes, localisation) | Commandes de la [section 6](#6-api-et-politiques-du-projet) (si autorisé) | à compléter |
| Quotas régionaux (`CPUS`, `IN_USE_ADDRESSES`) | `gcloud compute regions describe us-central1 --flatten="quotas[]" --format="table(quotas.metric,quotas.limit,quotas.usage)"` | à compléter |
| Image Debian 12 accessible | `gcloud compute images describe-from-family debian-12 --project=debian-cloud --format="value(name)"` | à compléter |
| Ressources préexistantes (réseau `default`, règles de firewall) | `gcloud compute networks list` ; `gcloud compute firewall-rules list` | à compléter |
| Rôle du compte étudiant sur le projet | Console, page IAM | à compléter |
| Délai entre la fin de l'`apply` et le premier `ping` réussi | Chronomètre | à compléter |
| Durées mesurées (`apply`, premier `site.yml`, `destroy`, total) | Chronomètre ; reporter dans le tableau de la [section 3](#3-durée-limitée-et-budget-temps) | à compléter |
| Écarts constatés avec les résultats attendus du README | Répétition générale | à compléter |

L'IP publique du poste n'est pas à reporter ici (donnée personnelle) : vérifier seulement
qu'elle ne change pas pendant la session (`curl -4 -s https://ifconfig.me`).

Après la première session : reporter la durée et les contraintes confirmées dans la section
« Contraintes du lab GCP » du [README](../README.md), et retirer de ce document les mentions
« à compléter » correspondantes.
