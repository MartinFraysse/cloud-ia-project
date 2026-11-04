# Référence des variables

Ce document recense **toutes les variables du socle** : où chacune est définie, ce qu'elle fait,
sa valeur par défaut et son niveau de précédence. Il couvre Ansible (rôles, `group_vars`,
inventaires, coffre Vault, inventaire dynamique, rôle public `geerlingguy.nginx`), Terraform
(racine et modules) et les variables d'environnement shell.

Documents liés : [README principal](../README.md) · [décisions techniques](decisions.md) ·
[runbooks](runbooks.md) · [dépannage](troubleshooting.md) · README des rôles
[`common`](../ansible/roles/common/README.md), [`webserver`](../ansible/roles/webserver/README.md),
[`fleetinfo`](../ansible/roles/fleetinfo/README.md) · README des modules Terraform
[`network`](../terraform/modules/network/README.md), [`compute`](../terraform/modules/compute/README.md).

Sauf mention contraire, les chemins Ansible sont relatifs au dossier `ansible/` (répertoire de
travail du controller : `/workspace/ansible`) et les chemins Terraform au dossier `terraform/`.

## Sommaire

1. [Précédence Ansible appliquée au projet](#1-précédence-ansible-appliquée-au-projet)
2. [Variables partagées : `group_vars/all/vars.yml`](#2-variables-partagées--group_varsallvarsyml)
3. [Variables d'environnement : local et cloud côte à côte](#3-variables-denvironnement--local-et-cloud-côte-à-côte)
4. [Secrets : `vault.yml`, convention `vault_`, `no_log`](#4-secrets--vaultyml-convention-vault_-no_log)
5. [Variables de rôle](#5-variables-de-rôle)
6. [Variables fournies par l'inventaire dynamique (`gce_*`)](#6-variables-fournies-par-linventaire-dynamique-gce_)
7. [Variables spéciales et facts utilisés](#7-variables-spéciales-et-facts-utilisés)
8. [Variables de `geerlingguy.nginx` surchargées](#8-variables-de-geerlingguynginx-surchargées)
9. [Variables Terraform](#9-variables-terraform)
10. [Cohérence entre Terraform, Ansible et Docker Compose](#10-cohérence-entre-terraform-ansible-et-docker-compose)
11. [Variables d'environnement shell](#11-variables-denvironnement-shell)
12. [Changer la version = 1 variable, 1 endroit](#12-changer-la-version--1-variable-1-endroit)

---

## 1. Précédence Ansible appliquée au projet

Ansible (ansible-core 2.17) définit 22 niveaux de précédence
([documentation officielle](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)).
Le socle n'en utilise qu'une partie. Les numéros ci-dessous sont ceux de la documentation
officielle ; ils servent de référence dans la colonne « Niveau » de tous les tableaux de ce document.

```
 PRÉCÉDENCE CROISSANTE : une ligne l'emporte sur toutes celles situées au-dessus d'elle

 N°  Niveau Ansible                          Où, dans le socle
 ──  ──────────────────────────────────────  ──────────────────────────────────────────────────────────
  2  defaults de rôle                        roles/{common,webserver,fleetinfo}/defaults/main.yml
                                             roles/geerlingguy.nginx/defaults/main.yml (rôle public)
  4  group_vars "all" de l'INVENTAIRE        inventories/local/group_vars/all.yml   (banc local)
                                             inventories/cloud/group_vars/all.yml   (GCP)
  5  group_vars "all" du PLAYBOOK            group_vars/all/vars.yml + group_vars/all/vault.yml
  8  variables d'hôte de l'inventaire        gce_*, ansible_host (plugin google.cloud.gcp_compute)
 11  facts                                   ansible_facts.*, ansible_local.fleetinfo (fait local)
 15  vars de rôle                            roles/*/vars/main.yml
                                             + mot-clé vars de la dépendance geerlingguy.nginx
                                               (roles/webserver/meta/main.yml)
 17  vars de tâche                           calculs locaux à une tâche (rôle fleetinfo)
 18  include_vars                            vars/Debian.yml de geerlingguy.nginx
 19  set_fact / register                     fleetinfo_active_dir, fleetinfo_deploy_status, ...
 21  paramètres d'include                    rollback : include_tasks deploy.yml avec vars
 22  extra vars (-e)                         ligne de commande : l'emportent TOUJOURS
```

Niveaux **non utilisés** : 3 (variables de groupe écrites dans le fichier d'inventaire : `hosts.yml`
n'en porte aucune), 6 et 7 (`group_vars/<groupe>.yml` autre que `all`), 9 et 10 (`host_vars/`),
12 à 14 (`vars`, `vars_prompt`, `vars_files` de play : aucune variable métier dans les playbooks),
16 (vars de bloc), 20 (paramètres de rôle en ligne).

### Règles de placement adoptées

| Nature de la variable | Emplacement | Niveau | Exemple |
|---|---|---|---|
| Valeur par défaut surchargeable d'un rôle, préfixée par le nom du rôle | `roles/<rôle>/defaults/main.yml` | 2 | `fleetinfo_keep_releases` |
| Ce qui diffère entre local et cloud | `inventories/<env>/group_vars/all.yml` (les deux fichiers) | 4 | `socle_env` |
| Valeur commune aux deux environnements, ou partagée entre plusieurs rôles | `group_vars/all/vars.yml` | 5 | `fleetinfo_version`, `socle_http_port` |
| Secret | `group_vars/all/vault.yml` (chiffré), préfixe `vault_`, référencé dans `vars.yml` | 5 | `vault_webserver_status_password` |
| Constante interne d'un rôle (chemin Debian, format) | `roles/<rôle>/vars/main.yml` | 15 | `webserver_site_path` |
| Valeur ponctuelle (démonstration, test) | `-e` en ligne de commande | 22 | `fleetinfo_simulate_failure` |

### Pièges de précédence à connaître

- **`group_vars/all/vars.yml` (niveau 5) écrase les `group_vars` d'inventaire `all` (niveau 4).**
  Une même clé ne doit donc pas être définie aux deux endroits : les clés propres à un
  environnement vivent **uniquement** dans `inventories/<env>/group_vars/all.yml`.
- **Un fichier `inventories/<env>/group_vars/web.yml` (niveau 6) l'emporterait sur
  `group_vars/all/vars.yml` (niveau 5).** Un tel fichier n'existe pas aujourd'hui ; en créer un
  pour y mettre `fleetinfo_version` casserait la règle « 1 variable, 1 endroit » (section 12).
- **Les `vars/main.yml` (niveau 15) ne sont pas surchargeables par les `group_vars`** : seuls
  les niveaux 16 à 22 passent au-dessus (vars de bloc et de tâche, `include_vars`, `set_fact`,
  paramètres de rôle et d'include, extra vars). C'est voulu (constantes internes), mais une
  valeur posée dans `group_vars` pour `webserver_site_path`, par exemple, serait silencieusement
  ignorée.
- **Les `group_vars` de playbook ne sont chargés que pour un playbook situé dans `ansible/`**
  (à côté de `group_vars/`). C'est pourquoi `site.yml` et `rollback.yml` sont à la racine de
  `ansible/` et qu'il n'existe pas de dossier `playbooks/` ([ADR-09](decisions.md)).
- **Extra vars et `rollback.yml`** : `rollback.yml` impose la version cible à `deploy.yml` par un
  paramètre d'include (niveau 21). Un `-e fleetinfo_version=...` (niveau 22) l'emporterait et
  ferait basculer vers une autre release que la cible. Avec `rollback.yml`, utiliser
  **uniquement** `-e fleetinfo_rollback_version=X.Y.Z`.
- **Type des extra vars** : `-e cle=valeur` produit une chaîne. Le code convertit explicitement
  (`| bool`, `| int`) et `meta/argument_specs.yml` valide les types ; pour passer un vrai type,
  utiliser la forme JSON : `-e '{"fleetinfo_keep_releases": 2}'`.

### Vérifier la valeur effective d'une variable

Dans le controller (`cd local && docker compose exec controller bash`, on arrive dans
`/workspace/ansible`) :

```bash
ansible web -m ansible.builtin.debug -a var=fleetinfo_version
```

Résultat attendu (vérifié sur le banc local ; sortie au format YAML car `ansible.cfg` fixe
`callback_result_format = yaml`) :

```
node1 | SUCCESS =>
    fleetinfo_version: 1.0.0
node2 | SUCCESS =>
    fleetinfo_version: 1.0.0
```

Lancée depuis `/workspace/ansible`, cette commande charge l'inventaire et les `group_vars`
(inventaire, et playbook car ils sont lus dans le répertoire courant), mais **pas les defaults
des rôles** : une variable définie uniquement dans `defaults/main.yml` y apparaît comme
`fleetinfo_keep_releases: VARIABLE IS NOT DEFINED!` (vérifié). Côté cloud, ajouter
`-i inventories/cloud/fleet.gcp.yml`.

`ansible-inventory --host node1` liste aussi les variables d'un hôte (inventaire et `group_vars`,
sans les defaults des rôles), **non résolues** : une valeur comme `"{{ socle_app_root }}"` est
affichée telle quelle (vérifié). **Attention :** cette commande, comme `debug var=...`, affiche
en clair les valeurs déchiffrées du coffre Vault. Ne jamais copier sa sortie dans un ticket ou
un canal de discussion.

---

## 2. Variables partagées : `group_vars/all/vars.yml`

Fichier : [`ansible/group_vars/all/vars.yml`](../ansible/group_vars/all/vars.yml).
Niveau **5** (group_vars « all » du playbook) : chargé quel que soit l'inventaire, il écrase les
defaults des rôles (2) et les `group_vars` d'inventaire `all` (4).

Les variables `socle_*` ne sont préfixées par aucun rôle car elles sont **partagées** : elles
sont définies une seule fois et les variables préfixées des rôles y font référence.

| Variable | Valeur | Ce qu'elle fait | Écrase le default de |
|---|---|---|---|
| `fleetinfo_version` | `"1.0.0"` | Version de Fleet Info à déployer. **Seul endroit à modifier pour livrer une version** (section 12). | `fleetinfo` (`"1.0.0"`) |
| `socle_http_port` | `80` | Port HTTP du site, défini une fois pour nginx et pour le contrôle de santé. Doit rester égal à `http_port` (Terraform) et au port conteneur publié par `local/docker-compose.yml`. | — |
| `webserver_listen_port` | `"{{ socle_http_port }}"` | Port d'écoute de nginx (rôle `webserver`). | `webserver` (`80`) |
| `fleetinfo_health_port` | `"{{ socle_http_port }}"` | Port interrogé par le contrôle de santé `/health` (rôle `fleetinfo`). | `fleetinfo` (`80`) |
| `socle_app_root` | `/opt/fleetinfo` | Racine de l'application, partagée par `fleetinfo` (qui y crée `releases/` et `current`) et `webserver` (qui sert `current`). | — |
| `fleetinfo_base_dir` | `"{{ socle_app_root }}"` | Racine utilisée par le rôle `fleetinfo`. | `fleetinfo` (`/opt/fleetinfo`) |
| `webserver_document_root` | `"{{ socle_app_root }}/current"` | Racine servie par nginx : le lien vers la release active. | `webserver` (`/opt/fleetinfo/current`) |
| `common_motd_extra_lines` | 3 lignes (ci-dessous) | Lignes ajoutées à la bannière `/etc/motd` : emplacement de la release active, du journal de déploiement et du site nginx. | `common` (`[]`) |
| `webserver_status_password` | `"{{ vault_webserver_status_password }}"` | Mot de passe de `/status`, simple **référence** à la variable chiffrée (section 4). | `webserver` (aucun : obligatoire) |

Valeur de `common_motd_extra_lines` :

```yaml
common_motd_extra_lines:
  - "Application   : Fleet Info (release active : {{ socle_app_root }}/current)"
  - "Journal       : /var/log/fleetinfo/deploy.log"
  - "Site nginx    : /etc/nginx/sites-enabled/fleetinfo.conf"
```

Valeurs effectives vérifiées sur le banc local : `webserver_listen_port` = `80` (entier),
`fleetinfo_health_port` = `80`, `fleetinfo_base_dir` = `/opt/fleetinfo`,
`webserver_document_root` = `/opt/fleetinfo/current`.

---

## 3. Variables d'environnement : local et cloud côte à côte

Les **seules** différences entre les deux environnements sont portées par l'inventaire et ses
`group_vars` ; aucun rôle ne contient de condition sur l'environnement ([ADR-01](decisions.md)).

Fichiers :
[`inventories/local/group_vars/all.yml`](../ansible/inventories/local/group_vars/all.yml) et
[`inventories/cloud/group_vars/all.yml`](../ansible/inventories/cloud/group_vars/all.yml),
niveau **4**. Chacun n'est chargé qu'avec l'inventaire de son dossier.

| Variable | Local (`inventories/local/`) | Cloud (`inventories/cloud/`) | Ce qu'elle fait |
|---|---|---|---|
| `ansible_user` | `ansible` | `ansible` | Compte SSH. Local : créé dans l'image des nœuds (`local/node/Dockerfile`). Cloud : créé par l'agent invité GCE depuis la métadonnée `ssh-keys` (Terraform `ssh_user`) ; l'inventaire dynamique le déduit de cette métadonnée (`compose`, niveau 8), la valeur du `group_vars` cloud ne sert que de repli. Sudo sans mot de passe dans les deux cas. |
| `ansible_ssh_private_key_file` | `/root/.ssh/fleet_key` | `/root/.ssh/fleet_key` | Clé privée de déploiement, recopiée en mode 600 par `local/controller/entrypoint.sh` depuis `local/ssh/fleet_key`. Même clé pour les deux environnements. |
| `ansible_host_key_checking` | `false` | non définie (défaut Ansible : vérification active) | Local : les nœuds sont reconstruits à volonté (nouvelles clés d'hôte), la vérification n'apporte rien sur le réseau Docker privé. |
| `ansible_ssh_common_args` | non définie | `"-o StrictHostKeyChecking=accept-new"` | Cloud : accepte et mémorise la clé d'hôte d'une VM neuve (TOFU), refuse une clé qui change ensuite pour la même IP. |
| `socle_env` | `local` | `cloud` | Identité de l'environnement, affichée par `common` (bannière) et `fleetinfo` (page, `/health`). |
| `fleetinfo_cloud_zone` | non définie : default du rôle `""` | `"{{ gce_zone }}"` | Zone affichée sur la page. Vide = section « Cloud » absente. |
| `fleetinfo_cloud_machine_type` | non définie : default du rôle `""` | `"{{ gce_machineType }}"` | Type de machine affiché sur la page. |
| `fleetinfo_cloud_public_ip` | non définie : default du rôle `""` | `"{{ ansible_host }}"` | IP publique affichée dans la section « Identité ». |

Ce que fournit l'inventaire lui-même :

| Élément | Local (`inventories/local/hosts.yml`) | Cloud (`inventories/cloud/fleet.gcp.yml`) |
|---|---|---|
| Type d'inventaire | Statique (YAML) | Dynamique, plugin `google.cloud.gcp_compute` |
| Hôtes | `node1`, `node2` | Nom des VM (`hostnames: name`) : `fleetinfo-web-1`, `fleetinfo-web-2`... |
| `ansible_host` | Absent : le nom est résolu par le DNS du réseau Docker `labnet` | `networkInterfaces[0].accessConfigs[0].natIP` (`compose`), niveau 8 |
| Groupes | `web` | `web` (label `role`), `env_cloud` (label `env`), `zone_<zone>` (ex. `zone_us_central1_f`) |
| Variables d'hôte | Aucune | `gce_*` (section 6) |
| Fichier versionné | Oui | Non : généré par `scripts/prepare-cloud-inventory.sh` depuis `fleet.gcp.yml.example` (contient le `project_id`) |

L'inventaire par défaut est le banc local (`inventory = inventories/local/hosts.yml` dans
`ansible.cfg`) ; le cloud se cible explicitement avec `-i inventories/cloud/fleet.gcp.yml`.

Résultat attendu de `ansible-inventory --graph` en local (vérifié) :

```
@all:
  |--@ungrouped:
  |--@web:
  |  |--node1
  |  |--node2
```

---

## 4. Secrets : `vault.yml`, convention `vault_`, `no_log`

### Le coffre

| Élément | Valeur |
|---|---|
| Fichier chiffré | [`ansible/group_vars/all/vault.yml`](../ansible/group_vars/all/vault.yml) (en-tête `$ANSIBLE_VAULT;1.1;AES256`), niveau **5** |
| Variable contenue | `vault_webserver_status_password` : mot de passe du compte `exploitation` de `/status`, 24 caractères aléatoires |
| Référencée par | `webserver_status_password: "{{ vault_webserver_status_password }}"` dans `group_vars/all/vars.yml` |
| Mot de passe du coffre | Fichier `socle-web-automatise/.vault_pass` (`/workspace/.vault_pass` dans le controller), ignoré par Git (`.vault_pass*`), transmis par l'équipe hors Git. Dans le controller, il est lu par le script `/usr/local/bin/fleet-vault-pass` (`ANSIBLE_VAULT_PASSWORD_FILE`, section 11) ; hors controller, par `vault_password_file = ../.vault_pass` d'`ansible.cfg`. |

### La convention `vault_`

Toute valeur secrète est rangée dans `vault.yml` sous un nom préfixé `vault_`, puis
**référencée** par une variable en clair dans `vars.yml`. On sait ainsi quelles variables sont
secrètes et d'où elles viennent sans déchiffrer le coffre :

```bash
grep -n "vault_" group_vars/all/vars.yml
```

Résultat attendu :

```
38:webserver_status_password: "{{ vault_webserver_status_password }}"
```

### Protection à l'exécution

| Mécanisme | Où | Effet |
|---|---|---|
| `no_log: true` | Tâche « Créer le compte d'accès à la page /status » (`roles/webserver/tasks/main.yml`) | Le mot de passe n'apparaît jamais dans la sortie, même en `-vvv` (« the output has been hidden due to the fact that 'no_log: true' was specified for this result »). |
| `no_log: true` sur l'option | `webserver_status_password` dans `roles/webserver/meta/argument_specs.yml` | La valeur est masquée dans les messages de validation des arguments. |
| `required: true` | Même option | Le rôle refuse de s'exécuter sans mot de passe : aucune valeur par défaut n'existe. |
| htpasswd haché | `/etc/nginx/fleetinfo-status.htpasswd` (`apr_md5_crypt`) | Le mot de passe en clair n'est jamais écrit sur le serveur ([ADR-11](decisions.md)). |

### Commandes (dans le controller, depuis `/workspace/ansible`)

| Besoin | Commande | Résultat attendu |
|---|---|---|
| Lire le mot de passe de `/status` | `ansible-vault view group_vars/all/vault.yml` | Le contenu en clair du coffre, dont la ligne `vault_webserver_status_password: ...` (aucune invite : le mot de passe du coffre est lu dans `../.vault_pass`) |
| Changer le mot de passe de `/status` | `ansible-vault edit group_vars/all/vault.yml`, puis `ansible-playbook site.yml --tags webserver` | La tâche « Créer le compte d'accès à la page /status » est `changed` (sortie masquée) ; `curl -u exploitation:<nouveau> http://localhost:8081/status` renvoie 200 |
| Changer le mot de passe du coffre | `ansible-vault rekey --new-vault-password-file /chemin/nouveau group_vars/all/vault.yml`, puis remplacer le contenu de `../.vault_pass` | `Rekey successful` ; `ansible-vault view` fonctionne avec le nouveau fichier |

Procédure complète : [runbooks](runbooks.md).

### Données sensibles hors Ansible

| Donnée | Où | Protection |
|---|---|---|
| IP publique de l'opérateur | Terraform `ssh_source_ranges` (racine et module `network`) | `sensitive = true` : `terraform plan` affiche `(sensitive value)`. La valeur reste lisible dans `terraform.tfvars` et dans le state, tous deux ignorés par Git. |
| `project_id` de la session | `terraform.tfvars`, `inventories/cloud/fleet.gcp.yml` | Fichiers non versionnés ; le modèle versionné contient `__GCP_PROJECT_ID__`. |
| Identifiants GCP (ADC) | `.secrets/gcp-adc.json` | Non versionné, dossier 700, fichier 600. |
| Clé SSH privée | `local/ssh/fleet_key` | Non versionnée, générée par `local/scripts/generate-keys.sh`. |

---

## 5. Variables de rôle

Chaque rôle sépare ses **defaults** (niveau 2, surchargeables, préfixés par le nom du rôle) de
ses **constantes** (`vars/main.yml`, niveau 15, non destinées à être surchargées). Les types sont
validés par `meta/argument_specs.yml` avant la première tâche de chaque rôle. Le détail du
fonctionnement de chaque rôle est dans son README.

### 5.1 Rôle `common`

Defaults : [`roles/common/defaults/main.yml`](../ansible/roles/common/defaults/main.yml) (niveau 2).

| Variable | Défaut | Valeur effective dans le socle | Description |
|---|---|---|---|
| `common_packages` | `[curl, vim, ca-certificates, tzdata]` | identique | Paquets de base installés sur tout serveur. |
| `common_apt_cache_valid_time` | `3600` | identique | Durée (s) pendant laquelle le cache apt est considéré comme frais : évite un `apt-get update` à chaque exécution. |
| `common_timezone` | `"Europe/Paris"` | identique | Fuseau horaire IANA du serveur. |
| `common_ops_user` | `"fleetops"` | identique | Compte d'exploitation, sans sudo. |
| `common_ops_user_groups` | `[adm, systemd-journal]` | identique | Groupes secondaires du compte : lecture de `/var/log/*` (`adm`) et de `journalctl` (`systemd-journal`). |
| `common_environment` | `"{{ socle_env \| default('inconnu') }}"` | `local` ou `cloud` (via `socle_env`, niveau 4) | Environnement affiché dans la bannière. |
| `common_motd_extra_lines` | `[]` | 3 lignes (`group_vars/all/vars.yml`, niveau 5) | Lignes libres ajoutées à la bannière. |
| `common_motd_footer` | `"Serveur géré par Ansible : aucune modification manuelle, passer par le dépôt Git."` | identique | Dernière ligne de la bannière. |

Constantes : [`roles/common/vars/main.yml`](../ansible/roles/common/vars/main.yml) (niveau 15).

| Variable | Valeur | Description |
|---|---|---|
| `common_motd_path` | `/etc/motd` | Bannière affichée après chaque connexion SSH (pam_motd). |

### 5.2 Rôle `webserver`

Defaults : [`roles/webserver/defaults/main.yml`](../ansible/roles/webserver/defaults/main.yml) (niveau 2).

| Variable | Défaut | Valeur effective dans le socle | Description |
|---|---|---|---|
| `webserver_listen_port` | `80` | `"{{ socle_http_port }}"` = `80` (niveau 5) | Port d'écoute HTTP du site. |
| `webserver_document_root` | `/opt/fleetinfo/current` | `"{{ socle_app_root }}/current"` = `/opt/fleetinfo/current` (niveau 5) | Racine servie : le lien `current` géré par `fleetinfo`. nginx le résout à chaque requête. |
| `webserver_status_user` | `"exploitation"` | identique | Compte autorisé sur `/status` (HTTP Basic). |
| `webserver_status_password` | aucun (obligatoire, secret) | `"{{ vault_webserver_status_password }}"` (niveau 5) | Mot de passe de ce compte (section 4). |
| `webserver_status_crypt_scheme` | `apr_md5_crypt` | identique | Algorithme du fichier htpasswd. Valeurs acceptées : `apr_md5_crypt`, `sha256_crypt`, `sha512_crypt`, `md5_crypt`. |
| `webserver_status_allowed_networks` | `[]` | identique | Plages IP autorisées sur `/status` **en plus** de l'authentification (vide = toutes). Ex. `["10.10.0.0/24"]`. |

Constantes : [`roles/webserver/vars/main.yml`](../ansible/roles/webserver/vars/main.yml) (niveau 15).

| Variable | Valeur | Description |
|---|---|---|
| `webserver_site_path` | `/etc/nginx/sites-enabled/fleetinfo.conf` | Fichier du site, inclus par le `nginx.conf` de `geerlingguy.nginx` (`sites-enabled/*`). |
| `webserver_status_htpasswd_path` | `/etc/nginx/fleetinfo-status.htpasswd` | Comptes autorisés sur `/status`. |
| `webserver_nginx_group` | `www-data` | Groupe des workers nginx sous Debian, propriétaire du htpasswd (lecture). |
| `webserver_access_log` | `/var/log/nginx/fleetinfo.access.log` | Journal d'accès du site. |
| `webserver_error_log` | `/var/log/nginx/fleetinfo.error.log` | Journal d'erreurs du site. |

### 5.3 Rôle `fleetinfo`

Defaults : [`roles/fleetinfo/defaults/main.yml`](../ansible/roles/fleetinfo/defaults/main.yml) (niveau 2).

| Variable | Défaut | Valeur effective dans le socle | Description |
|---|---|---|---|
| `fleetinfo_version` | `"1.0.0"` | `"1.0.0"` (`group_vars/all/vars.yml`, niveau 5) | Version à déployer (`X.Y.Z`). Le default n'est qu'une valeur de secours. |
| `fleetinfo_base_dir` | `/opt/fleetinfo` | `"{{ socle_app_root }}"` = `/opt/fleetinfo` (niveau 5) | Racine : `releases/<version>/` et lien `current`. |
| `fleetinfo_keep_releases` | `3` | identique | Nombre de releases conservées ; la release active et la précédente ne sont jamais supprimées. |
| `fleetinfo_environment` | `"{{ socle_env \| default('inconnu') }}"` | `local` ou `cloud` | Environnement affiché sur la page et dans `/health`. |
| `fleetinfo_cloud_zone` | `""` | local : `""` ; cloud : `"{{ gce_zone }}"` (niveau 4) | Zone GCP affichée (vide = section « Cloud » absente). |
| `fleetinfo_cloud_machine_type` | `""` | local : `""` ; cloud : `"{{ gce_machineType }}"` | Type de machine affiché. |
| `fleetinfo_cloud_public_ip` | `""` | local : `""` ; cloud : `"{{ ansible_host }}"` | IP publique affichée. |
| `fleetinfo_release_notes` | `"1.0.0"`, `"1.1.0"`, `"1.2.0"` (textes) | identique ; à compléter (ici ou par surcharge dans `group_vars/all/vars.yml`) lors d'une livraison | Notes de version affichées sur la page, par version (`dict`) ; une version absente du catalogue reste déployable, la section est alors omise. |
| `fleetinfo_health_host` | `127.0.0.1` | identique | Hôte interrogé par le contrôle de santé, depuis le serveur lui-même. |
| `fleetinfo_health_port` | `80` | `"{{ socle_http_port }}"` = `80` (niveau 5) | Port interrogé par le contrôle de santé. |
| `fleetinfo_health_path` | `/health` | identique | Chemin du contrôle de santé. |
| `fleetinfo_health_retries` | `5` | identique | Nombre de **nouvelles tentatives** (`retries`) après le premier appel à `/health` : 6 interrogations au total avant de déclarer la release défaillante. |
| `fleetinfo_health_delay` | `2` | identique | Secondes entre deux interrogations (environ 10 s d'attente au total avec les valeurs par défaut). |
| `fleetinfo_web_service` | `nginx` | identique | Service rechargé lors d'un retour arrière automatique. |
| `fleetinfo_deploy_log` | `/var/log/fleetinfo/deploy.log` | identique | Journal des déploiements (une ligne par tentative). |
| `fleetinfo_log_group` | `adm` | identique | Groupe propriétaire du journal (lecture par le compte d'exploitation). |
| `fleetinfo_simulate_failure` | `false` | identique ; `true` uniquement en `-e` | Démonstration : livre une release sans `health.json` pour provoquer le retour arrière. |
| `fleetinfo_rollback_version` | `""` | identique ; renseignée en `-e` | Cible de `rollback.yml` ; vide = release précédente mémorisée dans le fait local. |

Constantes : [`roles/fleetinfo/vars/main.yml`](../ansible/roles/fleetinfo/vars/main.yml) (niveau 15).
Les chemins sont évalués à l'usage : ils suivent automatiquement `fleetinfo_base_dir` et
`fleetinfo_version`.

| Variable | Valeur | Description |
|---|---|---|
| `fleetinfo_releases_dir` | `"{{ fleetinfo_base_dir }}/releases"` | Répertoire des releases. |
| `fleetinfo_current_link` | `"{{ fleetinfo_base_dir }}/current"` | Lien symbolique vers la release active. |
| `fleetinfo_release_dir` | `"{{ fleetinfo_releases_dir }}/{{ fleetinfo_version }}"` | Répertoire de la release demandée. |
| `fleetinfo_fact_dir` | `/etc/ansible/facts.d` | Répertoire des faits locaux Ansible. |
| `fleetinfo_fact_file` | `"{{ fleetinfo_fact_dir }}/fleetinfo.fact"` | Fait local `ansible_local.fleetinfo` (release active, précédente, date). |
| `fleetinfo_health_url` | `"http://{{ fleetinfo_health_host }}:{{ fleetinfo_health_port }}{{ fleetinfo_health_path }}"` | URL du contrôle de santé (`http://127.0.0.1:80/health`). |
| `fleetinfo_render_release` | `true` | Générer les fichiers de la release avant la bascule. Mis à `false` par `rollback.yml` (paramètre d'include, niveau 21). |
| `fleetinfo_deploy_kind` | `deploiement` | Type d'opération écrit dans le journal. Mis à `rollback-manuel` par `rollback.yml`. |
| `fleetinfo_version_pattern` | `'^[0-9]+\.[0-9]+\.[0-9]+$'` | Format accepté pour une version. |

Variables calculées pendant l'exécution (`set_fact`, niveau 19 ; ne pas les définir ailleurs) :

| Variable | Définie par la tâche | Contenu |
|---|---|---|
| `fleetinfo_active_dir` | « Mémoriser la release active avant bascule (cible d'un éventuel retour arrière) » | Cible actuelle du lien `current` (vide au premier déploiement). |
| `fleetinfo_active_version` | « Calculer le contexte du déploiement » | Version active avant bascule (N-1). |
| `fleetinfo_deploy_needed` | « Calculer le contexte du déploiement » | Vrai si `current` doit changer de release. |
| `fleetinfo_deployed_at` | « Dater le déploiement et identifier la release précédente » | Date affichée : celle de l'exécution si bascule, sinon celle du fait local. |
| `fleetinfo_recorded_previous` | Même tâche | Version précédente à mémoriser et afficher. |
| `fleetinfo_deploy_status` | Plusieurs tâches | `EN_COURS`, puis `SUCCES`, `ECHEC_ROLLBACK_OK`, `ECHEC_ROLLBACK_KO` ou `ECHEC_SANS_ROLLBACK`. |
| `fleetinfo_deploy_detail` | « Mémoriser la cause de l'échec » | Tâche en échec et message d'erreur, recopiés dans le journal. |
| `fleetinfo_rollback_target` | « Déterminer la version cible du retour arrière » (`tasks/rollback.yml`) | Version cible du retour arrière manuel. |

---

## 6. Variables fournies par l'inventaire dynamique (`gce_*`)

Source : plugin `google.cloud.gcp_compute` (collection `google.cloud` 1.15.0), configuré par
[`inventories/cloud/fleet.gcp.yml.example`](../ansible/inventories/cloud/fleet.gcp.yml.example)
([ADR-07](decisions.md)). Niveau **8** (variables d'hôte d'inventaire) : elles l'emportent sur
tous les `group_vars`. Le préfixe `gce_` (`vars_prefix`) évite toute collision avec les
variables du projet.

Le plugin copie **chaque attribut** renvoyé par l'API Compute Engine pour l'instance en variable
d'hôte préfixée. Il raccourcit au passage `zone` et `machineType` (nom court au lieu de l'URL
complète). Principales variables :

| Variable | Exemple de valeur | Utilisée par le socle |
|---|---|---|
| `gce_name` | `fleetinfo-web-1` | Nom d'hôte Ansible (`hostnames: name`) |
| `gce_zone` | `us-central1-f` (nom court) | Oui : `fleetinfo_cloud_zone` |
| `gce_zone_selflink` | URL complète de la zone | Non |
| `gce_machineType` | `e2-small` (nom court) | Oui : `fleetinfo_cloud_machine_type` |
| `gce_machineType_selflink` | URL complète du type de machine | Non |
| `gce_labels` | `{app: fleetinfo, env: cloud, role: web, team: plateforme}` | Indirectement : `keyed_groups` (groupes `web`, `env_cloud`) |
| `gce_tags` | `{items: [fleetinfo-web], fingerprint: ...}` | Non (le tag sert au firewall) |
| `gce_status` | `RUNNING` | Indirectement : filtre `status = RUNNING` |
| `gce_networkInterfaces` | Liste ; `[0].networkIP` = IP interne, `[0].accessConfigs[0].natIP` = IP publique | Oui : `ansible_host` (`compose`) |
| `gce_metadata` | `{ssh-keys: "ansible:ssh-ed25519 ...", enable-oslogin: "FALSE"}` | Oui : `ansible_user` (`compose`, partie avant `:` de `ssh-keys`) |
| `gce_project` | `qwiklabs-gcp-00-0123456789ab` | Non |
| `gce_image` | `null` : l'option `retrieve_image_info` du plugin n'est pas activée (lecture de l'image coûteuse en appels API) | Non |
| `gce_id`, `gce_selfLink`, `gce_creationTimestamp`, `gce_disks`... | Autres attributs bruts de l'API | Non |

Options du plugin, variables et groupes construits par sa configuration :

| Élément | Définition dans `fleet.gcp.yml` | Résultat |
|---|---|---|
| Projet | `projects: [__GCP_PROJECT_ID__]` dans le modèle, remplacé par `scripts/prepare-cloud-inventory.sh` (`terraform output -raw project_id`) | Projet interrogé ; aucune variable d'environnement n'existe pour cette option, d'où la génération du fichier |
| Authentification | `auth_kind: application` | Application Default Credentials lues dans le fichier désigné par `GOOGLE_APPLICATION_CREDENTIALS` (section 11) |
| Nom d'hôte | `hostnames: [name]` | Nom de la VM (`fleetinfo-web-1`...) |
| Préfixe | `vars_prefix: gce_` | Toutes les variables d'hôte brutes sont préfixées `gce_` |
| Sélection | `filters: [labels.app = fleetinfo, status = RUNNING]` | Seules les VM étiquetées par Terraform et démarrées ; filtre envoyé à l'API : `(labels.app = fleetinfo) (status = RUNNING)` |
| `ansible_host` | `compose: ansible_host: networkInterfaces[0].accessConfigs[0].natIP` | IP publique éphémère de la VM |
| `ansible_user` | `compose: ansible_user: metadata['ssh-keys'].split(':')[0]` | Utilisateur créé par Terraform (`var.ssh_user`), déduit de la métadonnée `ssh-keys` : reste aligné sans être recopié. Repli : `ansible_user: ansible` de `inventories/cloud/group_vars/all.yml` (vérifié avec une réponse d'API simulée : `opsuser:ssh-ed25519 ...` donne `ansible_user: opsuser`) |
| Groupe `web` | `keyed_groups: key: labels.role, prefix: "", separator: ""` | Même nom que le groupe local : `site.yml` (`hosts: web`) inchangé |
| Groupe `env_cloud` | `keyed_groups: key: labels.env, prefix: env` | Ciblage ponctuel : `--limit env_cloud` |
| Groupe `zone_<zone>` | `keyed_groups: key: zone, prefix: zone` | Ex. `zone_us_central1_f` |

Résultat attendu (le comportement du plugin a été validé avec une réponse simulée de l'API ;
l'exécution sur un vrai projet reste à confirmer lors de la répétition générale) :

```bash
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
```

```
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

Pour voir toutes les variables `gce_*` d'une VM :
`ansible-inventory -i inventories/cloud/fleet.gcp.yml --host fleetinfo-web-1` (même
avertissement qu'en section 1 : la sortie contient aussi les valeurs déchiffrées du coffre).

---

## 7. Variables spéciales et facts utilisés

Ces variables ne sont définies dans aucun fichier du projet ; Ansible les fournit.

| Variable | Fournie par | Utilisation dans le socle |
|---|---|---|
| `ansible_managed` | `ansible.cfg` (`ansible_managed = Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : ...`) | En-tête de chaque fichier généré par template. Volontairement sans date ni chemin (idempotence). |
| `ansible_facts.*` | Collecte des facts (`gathering = smart` : une fois par hôte et par exécution) | Page Fleet Info, bannière, contrôles `assert` (distribution, version, `service_mgr`). |
| `ansible_facts.date_time.iso8601` | Facts | Date du déploiement lors d'une bascule (heure UTC de la collecte des facts). |
| `ansible_local.fleetinfo` | Fait local `/etc/ansible/facts.d/fleetinfo.fact`, relu à chaque collecte (niveau 11) | Date du dernier déploiement et version précédente ([ADR-13](decisions.md)). |
| `inventory_hostname` | Inventaire | Journal (`hote=`), messages d'erreur, pied de page. |
| `group_names` | Inventaire | Ligne « Groupes Ansible » de la page. |
| `ansible_check_mode` | `--check` | Bascule forcée en simulation, contrôle `/health` sauté. |
| `ansible_failed_task`, `ansible_failed_result` | Section `rescue` | Cause de l'échec écrite dans le journal. |

---

## 8. Variables de `geerlingguy.nginx` surchargées

Le rôle public `geerlingguy.nginx` 3.3.1 est une dépendance de `webserver`
([ADR-04](decisions.md), justification complète dans le
[README de `webserver`](../ansible/roles/webserver/README.md#rôle-public-geerlingguynginx)).

Surcharges : mot-clé `vars` de la dépendance dans
[`roles/webserver/meta/main.yml`](../ansible/roles/webserver/meta/main.yml). Elles sont fusionnées
au niveau des **vars de rôle (15)** : elles l'emportent sur les defaults du rôle public et sur
tous les `group_vars` ; seuls les niveaux 16 à 22 (dont les extra vars `-e`) passent au-dessus.
Ne pas tenter de les modifier dans `group_vars` : la valeur serait ignorée.

| Variable | Défaut du rôle public | Valeur du socle | Pourquoi |
|---|---|---|---|
| `nginx_remove_default_vhost` | `false` | `true` | Le site `default` de Debian écoute aussi sur 80 en `default_server` : `nginx -t` échouerait (« duplicate default server »). |
| `nginx_vhosts` | `[]` | `[]` | Identique au défaut, posé explicitement : le mécanisme de vhosts du rôle public n'est pas utilisé, le site est un template du rôle `webserver` avec sa propre chaîne de handlers. |
| `nginx_server_tokens` | `"on"` | `"off"` | Masque la version de nginx dans les en-têtes HTTP et les pages d'erreur. |
| `nginx_conf_template` | `"nginx.conf.j2"` | `"{{ playbook_dir }}/roles/webserver/templates/nginx.conf.j2"` | Enveloppe du rôle `webserver` : ajoute l'en-tête `ansible_managed` puis inclut tel quel le template du rôle public. `/etc/nginx/nginx.conf` reste validé par `nginx -t -c %s` avant d'être posé. |

Variables du rôle public **laissées à leur défaut** (niveau 2) et qui comptent pour
l'exploitation ; elles peuvent être surchargées dans `group_vars/all/vars.yml` si besoin :

| Variable | Défaut | Effet |
|---|---|---|
| `nginx_package_name` | `"nginx"` | Paquet Debian installé (nginx 1.22.1 sur Debian 12, constaté sur le banc local). |
| `nginx_service_state` | `started` | État du service. Le handler `reload nginx` du rôle public ne s'exécute que si cette valeur vaut `started`. |
| `nginx_service_enabled` | `true` | Service activé au démarrage. |
| `nginx_worker_processes` | nombre de vCPU (`ansible_facts.processor_vcpus`) | Processus workers. |
| `nginx_listen_ipv6` | `true` | Sans effet ici : ne concerne que les vhosts du rôle public (non utilisés). |

Constantes Debian du rôle public, chargées par `include_vars` depuis `vars/Debian.yml`
(niveau 18) : `nginx_conf_file_path: /etc/nginx/nginx.conf`,
`nginx_vhost_path: /etc/nginx/sites-enabled`,
`nginx_default_vhost_path: /etc/nginx/sites-enabled/default`, `__nginx_user: "www-data"`
(recopié dans `nginx_user` par `set_fact`). Elles sont cohérentes avec `webserver_site_path` et
`webserver_nginx_group`.

---

## 9. Variables Terraform

### 9.1 Précédence Terraform

Du plus faible au plus fort : `default` du bloc `variable` < variables d'environnement
`TF_VAR_<nom>` < `terraform.tfvars` < `terraform.tfvars.json` < `*.auto.tfvars` et
`*.auto.tfvars.json` (ordre alphabétique) < options `-var` et `-var-file` (dans l'ordre de la
ligne de commande). Le socle n'utilise que `terraform.tfvars`,
copié depuis [`terraform.tfvars.example`](../terraform/terraform.tfvars.example) et ignoré par
Git.

```bash
cd terraform && cp terraform.tfvars.example terraform.tfvars
```

Les cinq variables sans défaut (`project_id`, `region`, `zone`, `vm_count`,
`ssh_source_ranges`) doivent y être renseignées à chaque session de lab.

### 9.2 Variables racine : [`terraform/variables.tf`](../terraform/variables.tf)

| Variable | Type | Défaut | Sensible | Validation | Description | Utilisée par |
|---|---|---|---|---|---|---|
| `project_id` | `string` | aucun (obligatoire) | non | `^[a-z][a-z0-9-]{4,28}[a-z0-9]$` | Identifiant du projet GCP de la session de lab. | provider `google`, output `project_id` |
| `region` | `string` | aucun (obligatoire) | non | — | Région GCP du sous-réseau (ex. `us-central1`). | provider, `module.network` (`region`, nom du sous-réseau) |
| `zone` | `string` | aucun (obligatoire) | non | doit commencer par `"<region>-"` | Zone des VM (ex. `us-central1-f`). | provider, `module.compute`, output `zone` |
| `vm_count` | `number` | aucun (obligatoire) | non | entier de 1 à 10 | Nombre de VM web. | `module.compute.instance_count` |
| `ssh_source_ranges` | `list(string)` | aucun (obligatoire) | **oui** | au moins un CIDR IPv4 de préfixe `/16` minimum (`0.0.0.0/0`, `0.0.0.0/1`, IPv6 refusés) | Plages autorisées en SSH : IP publique de l'opérateur en `/32`. | `module.network` |
| `name_prefix` | `string` | `"fleetinfo"` | non | `^[a-z][a-z0-9-]{1,20}$` | Préfixe des noms de ressources. | noms du VPC, du sous-réseau et des VM |
| `subnet_cidr` | `string` | `"10.10.0.0/24"` | non | CIDR IPv4 valide | Plage du sous-réseau. | `module.network` |
| `http_port` | `number` | `80` | non | — | Port HTTP ouvert (égal à `socle_http_port` côté Ansible). | `module.network` |
| `ssh_port` | `number` | `22` | non | — | Port SSH ouvert aux seules `ssh_source_ranges`. | `module.network` |
| `http_source_ranges` | `list(string)` | `["0.0.0.0/0"]` | non | — | Plages autorisées en HTTP. | `module.network` |
| `network_tag` | `string` | `"fleetinfo-web"` | non | — | Tag réseau commun des VM, cible des règles de firewall. | `module.network` (`target_tag`), `module.compute` (`network_tags`), output `network_tag` |
| `machine_type` | `string` | `"e2-small"` | non | — | Type de machine des VM. | `module.compute` |
| `vm_image` | `string` | `"debian-cloud/debian-12"` | non | — | Image de démarrage (famille Debian 12). | `module.compute` (`image`) |
| `boot_disk_size_gb` | `number` | `10` | non | — | Taille du disque de démarrage (Go). | `module.compute` (`disk_size_gb`) |
| `boot_disk_type` | `string` | `"pd-balanced"` | non | — | Type du disque (`pd-standard`, `pd-balanced`, `pd-ssd`). | `module.compute` (`disk_type`) |
| `ssh_user` | `string` | `"ansible"` | non | — | Utilisateur créé par l'agent invité GCE ; c'est l'`ansible_user` du cloud. | `module.compute`, output `ssh_commands` |
| `ssh_public_key_path` | `string` | `"../local/ssh/fleet_key.pub"` | non | le fichier doit exister | Clé publique injectée dans les VM. Chemin relatif au répertoire où Terraform s'exécute (`terraform/`, ou `-chdir=terraform`). | `local.ssh_public_key` |
| `environment` | `string` | `"cloud"` | non | — | Valeur du label `env` (groupe Ansible `env_cloud`). | `local.vm_labels` |
| `server_role` | `string` | `"web"` | non | — | Valeur du label `role` (groupe Ansible `web`, ciblé par `site.yml`). | `local.vm_labels`, nom des VM |
| `team` | `string` | `"plateforme"` | non | — | Valeur du label `team`. | `local.vm_labels` |
| `app_name` | `string` | `"fleetinfo"` | non | — | Valeur du label `app` (filtre de l'inventaire dynamique). | `local.vm_labels` |

Valeurs calculées : [`terraform/locals.tf`](../terraform/locals.tf).

| Local | Valeur | Rôle |
|---|---|---|
| `vm_labels` | `{app = var.app_name, env = var.environment, role = var.server_role, team = var.team}` | Labels posés sur chaque VM, exploités par l'inventaire dynamique. |
| `ssh_public_key` | `trimspace(file(var.ssh_public_key_path))` | Contenu de la clé publique, sans retour à la ligne final (métadonnée stable). |

Noms obtenus avec les valeurs par défaut et `region = "us-central1"` : VPC `fleetinfo-vpc`,
sous-réseau `fleetinfo-subnet-us-central1`, règles `fleetinfo-vpc-allow-http` et
`fleetinfo-vpc-allow-ssh`, VM `fleetinfo-web-1`, `fleetinfo-web-2`...

### 9.3 Module `network` : [`modules/network/variables.tf`](../terraform/modules/network/variables.tf)

Toutes les entrées sont obligatoires (aucun défaut). Détail : [README du module](../terraform/modules/network/README.md).

| Variable | Type | Sensible | Description | Valeur passée par `main.tf` |
|---|---|---|---|---|
| `network_name` | `string` | non | Nom du VPC ; préfixe des noms des règles de firewall. | `"${var.name_prefix}-vpc"` |
| `subnet_name` | `string` | non | Nom du sous-réseau. | `"${var.name_prefix}-subnet-${var.region}"` |
| `region` | `string` | non | Région du sous-réseau. | `var.region` |
| `subnet_cidr` | `string` | non | Plage CIDR du sous-réseau. | `var.subnet_cidr` |
| `target_tag` | `string` | non | Tag réseau des VM ciblées par les règles. | `var.network_tag` |
| `http_port` | `number` | non | Port TCP HTTP autorisé en entrée. | `var.http_port` |
| `http_source_ranges` | `list(string)` | non | Plages autorisées sur le port HTTP. | `var.http_source_ranges` |
| `ssh_port` | `number` | non | Port TCP SSH autorisé en entrée. | `var.ssh_port` |
| `ssh_source_ranges` | `list(string)` | **oui** | Plages autorisées sur le port SSH. | `var.ssh_source_ranges` |

### 9.4 Module `compute` : [`modules/compute/variables.tf`](../terraform/modules/compute/variables.tf)

Détail : [README du module](../terraform/modules/compute/README.md).

| Variable | Type | Défaut | Description | Valeur passée par `main.tf` |
|---|---|---|---|---|
| `instance_count` | `number` | aucun | Nombre de VM à créer. | `var.vm_count` |
| `name_prefix` | `string` | aucun | Préfixe des noms de VM (suffixe `-1`, `-2`...). | `"${var.name_prefix}-${var.server_role}"` |
| `zone` | `string` | aucun | Zone des VM. | `var.zone` |
| `machine_type` | `string` | aucun | Type de machine. | `var.machine_type` |
| `image` | `string` | aucun | Image (ou famille) de démarrage. | `var.vm_image` |
| `disk_size_gb` | `number` | aucun | Taille du disque (Go). | `var.boot_disk_size_gb` |
| `disk_type` | `string` | aucun | Type du disque. | `var.boot_disk_type` |
| `subnetwork_id` | `string` | aucun | Identifiant du sous-réseau. | `module.network.subnet_id` |
| `network_tags` | `list(string)` | aucun | Tags réseau des VM. | `[var.network_tag]` |
| `labels` | `map(string)` | aucun (validation : clés `env`, `role`, `team` obligatoires) | Labels des VM. | `local.vm_labels` |
| `ssh_user` | `string` | aucun | Utilisateur SSH créé depuis `ssh-keys`. | `var.ssh_user` |
| `ssh_public_key` | `string` | aucun | Contenu de la clé publique (une ligne). | `local.ssh_public_key` |
| `enable_os_login` | `bool` | `false` | Active OS Login sur les VM. | non passée (défaut `false`) |

### 9.5 Sorties racine utiles : [`terraform/outputs.tf`](../terraform/outputs.tf)

| Output | Contenu |
|---|---|
| `network_name`, `subnet_name`, `subnet_cidr` | VPC, sous-réseau et sa plage |
| `firewall_rules`, `network_tag` | Règles créées et tag ciblé |
| `vm_names`, `vm_public_ips`, `vm_internal_ips` | Noms et IP des VM (IP par nom de VM) |
| `fleetinfo_urls`, `health_urls` | `http://<ip>/` et `http://<ip>/health` par VM (`:<port>` ajouté si `http_port` n'est pas 80) |
| `ssh_commands` | `ssh -i local/ssh/fleet_key ansible@<ip>` par VM, à lancer depuis la racine du socle (`socle-web-automatise/`) |
| `project_id`, `zone` | Paramètres de session ; `project_id` est lu par `scripts/prepare-cloud-inventory.sh` |

---

## 10. Cohérence entre Terraform, Ansible et Docker Compose

Certaines valeurs existent des deux côtés de la frontière Terraform / Ansible. Elles doivent
rester alignées ; aucune n'est synchronisée automatiquement.

| Valeur | Terraform | Ansible | Docker Compose | Si on la change |
|---|---|---|---|---|
| Port HTTP | `http_port = 80` | `socle_http_port: 80` | `"8081:80"`, `"8082:80"` (port conteneur) | Modifier les trois, puis `terraform apply` et `ansible-playbook site.yml` |
| Utilisateur SSH | `ssh_user = "ansible"` | `ansible_user: ansible` (cloud) | Utilisateur `ansible` de `local/node/Dockerfile` | Modifier `ssh_user` (Terraform) suffit côté cloud : `compose` le relit dans la métadonnée ; aligner aussi le repli de `inventories/cloud/group_vars/all.yml` |
| Clé SSH | `ssh_public_key_path = "../local/ssh/fleet_key.pub"` | `ansible_ssh_private_key_file: /root/.ssh/fleet_key` | `local/node/authorized_keys` | Le script conserve une clé existante : supprimer `local/ssh/`, relancer `local/scripts/generate-keys.sh`, puis `docker compose up -d --build` (depuis `local/`) et `terraform apply` |
| Label `app` | `app_name = "fleetinfo"` | filtre `labels.app = fleetinfo` (écrit en dur dans `fleet.gcp.yml.example`) | — | Modifier aussi le filtre, sinon l'inventaire est vide |
| Label `role` | `server_role = "web"` | groupe `web` (keyed_groups), `hosts: web` dans `site.yml` | groupe `web` de `hosts.yml` | Ne pas changer : le nom de groupe `web` est le contrat entre les deux environnements |
| Label `env` | `environment = "cloud"` | groupe `env_<valeur>` | — | Seul le nom du groupe secondaire change |
| Racine applicative | — | `socle_app_root: /opt/fleetinfo` | — | Une seule variable Ansible |

---

## 11. Variables d'environnement shell

| Variable | Où | Valeur | Rôle |
|---|---|---|---|
| `ANSIBLE_CONFIG` | Controller : `local/docker-compose.yml` (`environment`) et `.devcontainer/devcontainer.json` (`containerEnv`) | `/workspace/ansible/ansible.cfg` | Désigne explicitement la configuration Ansible. Nécessaire sous Windows : Ansible ignore un `ansible.cfg` situé dans un dossier accessible en écriture à tous, ce qui est le cas des montages Docker Desktop. |
| `ANSIBLE_VAULT_PASSWORD_FILE` | Controller : `local/docker-compose.yml` (`environment`) | `/usr/local/bin/fleet-vault-pass` | Script de l'image (source : `local/controller/read-vault-password.sh`) qui affiche la première ligne de `/workspace/.vault_pass`. Prioritaire sur `vault_password_file` d'`ansible.cfg`. Raison : sous Windows, un fichier monté apparaît exécutable (777) et Ansible tenterait d'**exécuter** `.vault_pass` au lieu de le lire. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Controller : `local/docker-compose.yml` | `/workspace/.secrets/gcp-adc.json` | Fichier d'identifiants lu par `google-auth` pour l'inventaire dynamique (`auth_kind: application`). Sans effet tant que le fichier n'existe pas (environnement local). |
| `GOOGLE_APPLICATION_CREDENTIALS` | Poste (facultative) | chemin d'un fichier d'identifiants | Si elle est définie, `scripts/prepare-cloud-inventory.sh` copie **ce** fichier dans `.secrets/gcp-adc.json` au lieu des ADC de gcloud. Le provider Google de Terraform la lit aussi (mécanisme ADC standard). |
| `CLOUDSDK_CONFIG` | Poste (facultative) | répertoire de configuration gcloud | `scripts/prepare-cloud-inventory.sh` y cherche `application_default_credentials.json`. Sans elle : `%APPDATA%/gcloud` sous Git Bash (Windows) s'il existe, sinon `$HOME/.config/gcloud`. |
| `container` | Image des nœuds (`ENV` de `local/node/Dockerfile`) | `docker` | Indique à systemd qu'il tourne dans un conteneur. |
| `DEBIAN_FRONTEND` | Image des nœuds (`ENV` de `local/node/Dockerfile`) | `noninteractive` | apt sans questions interactives pendant le build. |

Variables **non utilisées**, volontairement : aucune variable `TF_VAR_*` (les valeurs passent par
`terraform.tfvars`) ; aucune variable `GCP_*` pour l'inventaire (les options sont dans
`fleet.gcp.yml`, et l'option `projects` n'a pas de variable d'environnement, d'où la génération
du fichier : [ADR-07](decisions.md)).

---

## 12. Changer la version = 1 variable, 1 endroit

La version de Fleet Info est **une seule variable**, `fleetinfo_version`, définie à **un seul
endroit** : [`ansible/group_vars/all/vars.yml`](../ansible/group_vars/all/vars.yml), ligne
`fleetinfo_version: "1.0.0"`.

```bash
grep -rn "^fleetinfo_version:" ansible/
```

Résultat attendu (depuis `socle-web-automatise/`) :

```
ansible/roles/fleetinfo/defaults/main.yml:8:fleetinfo_version: "1.0.0"
ansible/group_vars/all/vars.yml:13:fleetinfo_version: "1.0.0"
```

La première ligne est la valeur de secours du rôle (niveau 2) ; elle est toujours écrasée par
`group_vars/all/vars.yml` (niveau 5) et ne doit pas être modifiée pour livrer une version.

Tout le reste en découle automatiquement : `fleetinfo_release_dir`
(`/opt/fleetinfo/releases/<version>`), la cible du lien `current`, la version attendue par le
contrôle `/health`, le contenu de la page et de `health.json`, le fait local et la ligne du
journal.

Procédure (détaillée dans les [runbooks](runbooks.md)) :

1. Modifier `fleetinfo_version` dans `ansible/group_vars/all/vars.yml` (ex. `"1.1.0"`), committer.
2. Dans le controller : `ansible-playbook site.yml --tags fleetinfo` (ou `site.yml` complet ;
   ajouter `-i inventories/cloud/fleet.gcp.yml` pour le cloud).
3. Résultat attendu : déploiement canari sur le premier serveur, puis sur tous les autres ;
   `PLAY RECAP` avec `failed=0`.
4. Vérification, sur le poste : `curl -s http://localhost:8081/health` renvoie
   `"version": "1.1.0"` (idem sur 8082 ; côté cloud : `terraform -chdir=terraform output health_urls`).

Un `-e fleetinfo_version=X.Y.Z` (niveau 22) permet un déploiement ponctuel, par exemple en
démonstration. Il ne remplace pas la modification de `vars.yml` : le `site.yml` suivant, lancé
sans `-e`, redéploierait la version écrite dans `vars.yml`. Même règle après un
`rollback.yml` : aligner `fleetinfo_version` sur la version restaurée.
