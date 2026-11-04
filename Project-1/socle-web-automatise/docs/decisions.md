# Décisions techniques (ADR)

Ce document recense les choix structurants du « Socle Web Automatisé » sous forme
d'*Architecture Decision Records* (ADR). Il s'adresse à l'équipe qui reprend le run : pour
chaque décision, il explique **pourquoi** le code est écrit ainsi, ce qui a été écarté et ce
que cela implique au quotidien.

- Format de chaque ADR : **Contexte / Décision / Justification / Alternatives écartées /
  Conséquences**. Quelques ADR ajoutent une rubrique propre à leur sujet (risques du rôle
  public pour l'ADR-04, cible entreprise pour l'ADR-05).
- La numérotation est **figée** : le code y renvoie. Exemples :
  [`ansible/requirements.yml`](../ansible/requirements.yml) et
  [`ansible/roles/webserver/meta/main.yml`](../ansible/roles/webserver/meta/main.yml) citent
  l'ADR-04, [`ansible/site.yml`](../ansible/site.yml) l'ADR-09,
  [`terraform/modules/compute/main.tf`](../terraform/modules/compute/main.tf) renvoie à ce
  document pour la désactivation d'OS Login (ADR-06), [`ansible/.ansible-lint`](../ansible/.ansible-lint)
  pour l'exclusion du rôle public (ADR-04). Une décision remplacée n'est jamais renumérotée :
  elle passe au statut « Remplacée par ADR-xx » et la nouvelle prend le numéro suivant.
- **Niveau de preuve** : « vérifié » signifie constaté sur le banc local le 2026-11-03 (VM
  Debian 13, Docker 29.9.2). Le cloud n'a **pas encore** été exécuté sur un vrai projet GCP :
  ce qui le concerne est un comportement **attendu**, à confirmer lors de la répétition
  générale.
- Documents liés : [README du socle](../README.md), [runbooks](runbooks.md),
  [référence des variables](variables.md), [dépannage](troubleshooting.md),
  [contraintes du lab GCP](lab-gcp.md).

## Index

| N° | Décision | Domaine | Code principalement concerné |
|---|---|---|---|
| [ADR-01](#adr-01--un-seul-code-ansible-pour-deux-environnements) | Un seul code Ansible pour deux environnements | Ansible | `ansible/inventories/*/group_vars/all.yml`, `ansible/group_vars/all/vars.yml` |
| [ADR-02](#adr-02--controller-ansible-conteneurisé-ansible-core-217-et-dépendances-épinglées-dans-le-projet) | Controller Ansible conteneurisé, ansible-core 2.17, dépendances épinglées dans le projet | Outillage | `local/controller/`, `ansible/ansible.cfg`, `ansible/requirements.yml` |
| [ADR-03](#adr-03--image-des-nœuds-locaux--debian-12-avec-systemd-en-pid-1) | Image des nœuds locaux : Debian 12 avec systemd en PID 1 | Local | `local/node/Dockerfile`, `local/docker-compose.yml` |
| [ADR-04](#adr-04--rôle-public-geerlingguynginx-331-pour-nginx-rôles-maison-pour-le-reste) | Rôle public `geerlingguy.nginx` 3.3.1, rôles maison pour le reste | Ansible | `ansible/requirements.yml`, `ansible/roles/webserver/meta/main.yml` |
| [ADR-05](#adr-05--state-terraform-local) | State Terraform local | Terraform | `terraform/` (absence de bloc `backend`) |
| [ADR-06](#adr-06--accès-ssh--clé-de-déploiement-injectée-par-métadonnée-ssh-limité-à-lip-de-lopérateur) | Accès SSH : clé injectée par métadonnée, SSH limité à l'IP de l'opérateur | Terraform / sécurité | `terraform/modules/compute/main.tf`, `terraform/modules/network/main.tf`, `terraform/variables.tf` |
| [ADR-07](#adr-07--inventaire-dynamique-googlecloudgcp_compute) | Inventaire dynamique `google.cloud.gcp_compute` | Ansible / cloud | `ansible/inventories/cloud/`, `scripts/prepare-cloud-inventory.sh` |
| [ADR-08](#adr-08--déploiement-applicatif-par-releases-contrôle-de-santé-retour-arrière-et-canari) | Déploiement par releases, contrôle de santé, retour arrière, canari | Ansible | `ansible/roles/fleetinfo/tasks/`, `ansible/site.yml`, `ansible/rollback.yml` |
| [ADR-09](#adr-09--plays-écrits-dans-siteyml-pas-de-dossier-playbooks) | Plays écrits dans `site.yml` (pas de dossier `playbooks/`) | Ansible | `ansible/site.yml`, `ansible/rollback.yml` |
| [ADR-10](#adr-10--validation-de-la-configuration-nginx-par-une-chaîne-de-handlers-reload-plutôt-que-restart) | Validation nginx par chaîne de handlers, reload plutôt que restart | Ansible | `ansible/roles/webserver/handlers/main.yml`, `ansible/roles/webserver/tasks/main.yml` |
| [ADR-11](#adr-11--gestion-des-secrets) | Gestion des secrets (Ansible Vault, htpasswd, variables sensibles Terraform) | Sécurité | `ansible/group_vars/all/`, `ansible/roles/webserver/`, `terraform/variables.tf` |
| [ADR-12](#adr-12--terraform-en-modules-locaux-count-et-validations-de-variables) | Terraform en modules locaux, `count`, validations de variables | Terraform | `terraform/main.tf`, `terraform/modules/`, `terraform/variables.tf`, `terraform/versions.tf` |
| [ADR-13](#adr-13--idempotence-de-la-page--date-de-déploiement-mémorisée-dans-un-fait-local) | Idempotence de la page : date de déploiement mémorisée dans un fait local | Ansible | `ansible/roles/fleetinfo/templates/`, `ansible/roles/fleetinfo/tasks/deploy.yml` |

Toutes les décisions ci-dessous ont le statut **Acceptée** à la date du 2026-11-03.

---

## ADR-01 — Un seul code Ansible pour deux environnements

**Contexte**

La DSI exige que les développeurs travaillent en local « avec le même code d'automatisation
que celui utilisé sur le cloud ». Les consignes interdisent les conditions du type
`when: env == 'local'` dans les rôles, sauf cas justifié. Les deux environnements diffèrent
pourtant sur quelques points : paramètres de connexion SSH, politique de vérification des clés
d'hôte, présence d'informations propres au cloud (zone, type de machine, IP publique).

**Décision**

- `site.yml`, `rollback.yml`, les rôles et les templates sont **strictement identiques** en
  local et sur le cloud. Seul l'inventaire passé à Ansible change :
  - local : `inventories/local/hosts.yml` (inventaire statique, inventaire par défaut de
    `ansible.cfg`) ;
  - cloud : `inventories/cloud/fleet.gcp.yml` (inventaire dynamique, voir ADR-07), passé avec
    `-i inventories/cloud/fleet.gcp.yml`.
- Les deux inventaires produisent le **même groupe `web`**, seul groupe ciblé par les plays
  (`hosts: web`).
- Les différences d'environnement vivent **uniquement** dans les `group_vars` d'inventaire,
  qui définissent les mêmes clés avec des valeurs différentes :

| Variable | `inventories/local/group_vars/all.yml` | `inventories/cloud/group_vars/all.yml` |
|---|---|---|
| `ansible_user` | `ansible` (créé dans l'image des nœuds) | `ansible` (créé par l'agent invité GCE à partir de la métadonnée `ssh-keys`) |
| `ansible_ssh_private_key_file` | `/root/.ssh/fleet_key` | `/root/.ssh/fleet_key` |
| Clé d'hôte SSH | `ansible_host_key_checking: false` | `ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"` |
| `socle_env` | `local` | `cloud` |
| `fleetinfo_cloud_zone` | non définie (défaut du rôle : `""`) | `"{{ gce_zone }}"` |
| `fleetinfo_cloud_machine_type` | non définie (défaut : `""`) | `"{{ gce_machineType }}"` |
| `fleetinfo_cloud_public_ip` | non définie (défaut : `""`) | `"{{ ansible_host }}"` |

- Ce qui est commun aux deux environnements (version de l'application `fleetinfo_version`,
  port HTTP `socle_http_port`, racine `socle_app_root`, référence au secret) est défini une
  seule fois dans [`ansible/group_vars/all/vars.yml`](../ansible/group_vars/all/vars.yml).

**Justification**

- Parité : ce qui a été validé sur le banc local se comporte de la même façon sur GCP ; un
  écart de comportement ne peut venir que de l'inventaire ou de ses `group_vars`, ce qui
  restreint fortement la zone de recherche en cas de problème.
- Évolutivité : ajouter une VM côté Terraform ne demande aucune modification du code Ansible
  (le label `role=web` suffit à la faire entrer dans le groupe `web`).
- La page Fleet Info s'adapte aux **données** et non au nom de l'environnement : le template
  `index.html.j2` affiche la section « Cloud · Google Compute Engine » si
  `fleetinfo_cloud_zone` ou `fleetinfo_cloud_machine_type` sont non vides. C'est la condition
  « champs cloud présents ou non » demandée par les consignes, sans aucun test sur `socle_env`.
- Vérifié : la page rendue avec les `group_vars` cloud (simulation sur le banc local) contient
  la section « Cloud · Google Compute Engine » avec la zone et le type de machine ; elle est
  absente avec les `group_vars` locales.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Conditions `when: socle_env == 'cloud'` dans les rôles | Interdit par les consignes ; multiplie les chemins d'exécution à tester. |
| Deux jeux de playbooks (un par environnement) | Divergence inévitable ; le banc local ne prouverait plus rien sur le cloud. |
| Variables d'environnement passées en `-e` à chaque commande | Oubli facile, non versionné ; les extra-vars écrasent tout et masquent les erreurs de placement. |

**Conséquences**

- **Règle de précédence à respecter** : les `group_vars` **de playbook**
  (`ansible/group_vars/all/`) ont une précédence **supérieure** aux `group_vars`
  **d'inventaire** pour le groupe `all` (`inventories/<env>/group_vars/all.yml`). Une variable
  qui diffère selon l'environnement ne doit donc **jamais** être ajoutée dans
  `group_vars/all/vars.yml`, sinon elle écraserait la valeur propre à l'environnement
  (détail : [variables.md](variables.md)).
- Ajouter un troisième environnement (par exemple `staging`) revient à créer
  `inventories/staging/` avec son inventaire (groupe `web`) et un `group_vars/all.yml`
  définissant les mêmes clés.

---

## ADR-02 — Controller Ansible conteneurisé, ansible-core 2.17 et dépendances épinglées dans le projet

**Contexte**

Ansible ne s'exécute pas nativement sous Windows et l'équipe utilise des postes hétérogènes
(Windows, macOS, Linux). Les versions d'Ansible et des collections doivent être identiques
pour tous, en local comme pour piloter le cloud. Les consignes demandent d'utiliser le poste
local (et non Cloud Shell) pour Terraform et `gcloud`, et autorisent WSL comme alternative au
conteneur.

**Décision**

- Un conteneur **controller** ([`local/controller/Dockerfile`](../local/controller/Dockerfile))
  sert de poste de contrôle Ansible pour les **deux** environnements :
  - image `python:3.12-slim` + `openssh-client`, `git`, `curl`, `vim`, `less` ;
  - dépendances Python épinglées dans
    [`local/controller/requirements.txt`](../local/controller/requirements.txt) :
    `ansible-core==2.17.14`, `ansible-lint==25.9.2`, `google-auth==2.62.1`,
    `requests==2.34.2` ;
  - le dossier `socle-web-automatise/` est monté sur `/workspace` ; le répertoire de travail
    est `/workspace/ansible` ;
  - `ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg`,
    `ANSIBLE_VAULT_PASSWORD_FILE=/usr/local/bin/fleet-vault-pass` et
    `GOOGLE_APPLICATION_CREDENTIALS=/workspace/.secrets/gcp-adc.json` sont positionnées par
    [`local/docker-compose.yml`](../local/docker-compose.yml) ;
  - `fleet-vault-pass` ([`local/controller/read-vault-password.sh`](../local/controller/read-vault-password.sh),
    copié dans l'image) **lit** `/workspace/.vault_pass` : sous Windows, un fichier monté
    apparaît exécutable (`777`) et Ansible l'exécuterait au lieu de le lire ;
  - l'entrypoint ([`local/controller/entrypoint.sh`](../local/controller/entrypoint.sh))
    recopie `local/ssh/fleet_key` vers `/root/.ssh/fleet_key` avec les droits `600` à chaque
    démarrage, et lance `ansible-galaxy install -r requirements.yml` si le rôle ou les
    collections sont absents du projet (simple avertissement sans Internet) ; `init: true` et
    `CMD ["sleep", "infinity"]` gardent le conteneur disponible pour
    `docker compose exec controller bash`.
- **ansible-core** (et non le paquet `ansible` complet) : seules les dépendances déclarées dans
  [`ansible/requirements.yml`](../ansible/requirements.yml) sont utilisées, installées
  **dans le projet** (`roles_path = roles`, `collections_path = collections` dans
  `ansible.cfg`, dossiers ignorés par Git) aux versions épinglées :
  `geerlingguy.nginx` 3.3.1, `google.cloud` 1.15.0, `community.general` 12.6.7.
- Terraform et `gcloud` restent installés **sur le poste** (pas dans le controller).
- [`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json) permet d'ouvrir le
  même controller dans VS Code (extension Dev Containers) ; il est facultatif.

**Justification**

- Même outillage, aux mêmes versions, sur tous les postes : une commande documentée produit
  le même résultat chez tout le monde, y compris chez le consultant.
- ansible-core + collections épinglées : il n'existe qu'une version de chaque collection dans
  le controller, celle de `requirements.yml`. Vérifié : la combinaison ansible-core 2.17.14 +
  `google.cloud` 1.15.0 + `community.general` 12.6.7 passe `ansible-lint` en profil
  `production` (`Passed: 0 failure(s), 0 warning(s)`) et donne `changed=0` au second passage.
- `community.general` 12 a retiré le callback `community.general.yaml` : la sortie YAML est
  obtenue avec `callback_result_format = yaml` dans `ansible.cfg`.
- Le montage du dépôt (et non une copie dans l'image) permet de modifier le code depuis le
  poste et de l'exécuter immédiatement dans le controller.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| WSL sur les postes Windows | Acceptée par les consignes, mais installation propre à chaque poste, versions qui dérivent d'un membre à l'autre ; ne règle rien pour macOS. Reste possible : voir la variante Windows du [README](../README.md). |
| `venv` Python sur le poste | Impossible sous Windows natif ; mêmes risques de dérive de versions. |
| Paquet `ansible` 10 (ansible-core 2.17 + collections fournies) | Beaucoup plus volumineux ; il embarque ses propres versions de `community.general` et `google.cloud`, ce qui crée deux versions concurrentes de la même collection et rend `ansible-galaxy collection list` ambigu. |
| Terraform et `gcloud` dans le controller | Duplique l'authentification `gcloud` dans le conteneur ; les consignes demandent d'utiliser le poste pour ces outils. |

**Conséquences**

- Docker (Docker Desktop sous Windows et macOS) est requis, **y compris** pour piloter le
  cloud.
- Le controller dépend des nœuds locaux (`depends_on` … `condition: service_healthy`) :
  `docker compose up` démarre aussi `node1` et `node2`, même pour un usage cloud. Le coût est
  faible une fois les images construites.
- `/root/.ssh/known_hosts` vit dans le conteneur (non monté) : il est perdu si le controller
  est recréé, sans conséquence grâce à `StrictHostKeyChecking=accept-new` côté cloud.
- **Dette technique** : ansible-core 2.17 est en fin de vie. Une montée de version (2.18 ou
  plus) est à planifier, avec revalidation des collections, d'`ansible-lint` et de
  l'idempotence (voir la section « Limites connues » du [README](../README.md)).

---

## ADR-03 — Image des nœuds locaux : Debian 12 avec systemd en PID 1

**Contexte**

Les consignes demandent des conteneurs « nœuds » Debian 12 qui **se comportent comme des VM** :
`systemd`, `sshd`, `python3`, `sudo`, gérés par Ansible via SSH avec les modules
`service`/`systemd` et des handlers. Le rôle `common` règle le fuseau horaire avec
`community.general.timezone`, qui passe par `timedatectl` (systemd-timedated via D-Bus). Les
consignes autorisent à reprendre les images et fichiers Compose des labs, à condition de
pouvoir les décrire et en expliquer le fonctionnement.

**Décision**

- Image construite localement depuis l'image officielle `debian:bookworm-slim`
  ([`local/node/Dockerfile`](../local/node/Dockerfile), reprise de `managed-node/` des labs) :
  - paquets `systemd`, `systemd-sysv`, `dbus`, `openssh-server`, `sudo`, `python3`, `curl`,
    `iproute2`, `procps` ;
  - variable `container=docker` (systemd saute les unités matérielles) ;
  - utilisateur `ansible` sudoer sans mot de passe (`/etc/sudoers.d/ansible`, mode `440`),
    comme l'utilisateur créé par l'agent invité sur une VM GCE ;
  - clé publique `local/node/authorized_keys` (produite par
    `local/scripts/generate-keys.sh`) copiée **au build** dans
    `/home/ansible/.ssh/authorized_keys` ;
  - `sshd` activé comme service systemd (`systemctl enable ssh`), `STOPSIGNAL SIGRTMIN+3`,
    `CMD ["/lib/systemd/systemd"]`.
- Exécution ([`local/docker-compose.yml`](../local/docker-compose.yml), ancre `x-node`) :
  `privileged: true`, `cgroup: host`, montage `/sys/fs/cgroup:/sys/fs/cgroup:rw`, `tmpfs`
  sur `/run` et `/run/lock`, healthcheck `systemctl is-active --quiet ssh` (toutes les 5 s,
  12 essais). Une seule image (`fleetinfo-local/node:debian12`) est partagée par tous les
  nœuds ; ports publiés `8081:80` (`node1`) et `8082:80` (`node2`) sur le réseau `labnet`.

**Justification**

- Même distribution que les VM GCP (image `debian-cloud/debian-12`) et même mode d'accès
  (SSH, utilisateur `ansible`, `sudo`) : le code Ansible ne fait aucune différence. Le rôle
  `common` le vérifie d'ailleurs en tête (assertion Debian 12 + `service_mgr == 'systemd'`).
- systemd en PID 1 rend utilisables `ansible.builtin.service` (reload de nginx, handlers),
  `community.general.timezone` et `journalctl`, exactement comme sur une VM.
- Image construite à partir de l'image officielle Debian, sans dépendance à une image tierce :
  contenu connu et auditable en un seul fichier.
- Le healthcheck sur `ssh` permet `docker compose up --wait` : la commande ne rend la main que
  lorsque Ansible peut se connecter, et le controller ne démarre qu'après les nœuds.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Image avec `sshd` en PID 1 (sans systemd) | Pas de gestionnaire de services : les modules `service`/`timezone` et les handlers de rechargement de nginx sont inutilisables ; le nœud ne se comporte plus comme une VM. |
| Images tierces `jrei/systemd-debian`, `geerlingguy/docker-debian12-ansible` | Dépendance à un mainteneur externe et à son rythme de mise à jour ; contenu à auditer ; l'image geerlingguy vise l'exécution d'Ansible *dans* le conteneur (tests de rôles), pas un nœud géré par SSH avec notre utilisateur et notre clé. |
| VM locales (Vagrant + VirtualBox ou Hyper-V) | Lourd et lent ; conflits d'hyperviseur avec Docker Desktop sous Windows ; les consignes prévoient Docker Desktop + Docker Compose. |

**Conséquences**

- Conteneurs **privilégiés** : acceptable pour un banc local, **jamais** en production.
- Fonctionnement constaté avec un hôte Docker récent en cgroups v2 (Docker 29.9.2) ; un hôte
  en cgroups v1 n'a pas été testé.
- La clé publique est intégrée **au build** : renouveler la clé impose
  `docker compose up -d --build`.
- Les clés d'hôte SSH sont générées **à la construction de l'image** (installation
  d'`openssh-server`) : elles sont identiques sur tous les nœuds (image partagée) et changent
  dès que cette couche est reconstruite (build sans cache, cache purgé par
  `docker builder prune`, modification du `Dockerfile` en amont). La vérification est donc
  désactivée en local (`ansible_host_key_checking: false`), sans enjeu sur ce réseau Docker
  privé.
- Différences résiduelles avec une VM : noyau partagé avec l'hôte (la page affiche le noyau
  de l'hôte Docker), pas d'agent invité ni de métadonnées GCE, vCPU et mémoire de l'hôte.
- Ajouter un nœud local : quelques lignes dans `docker-compose.yml` (modèle `node3` commenté,
  à ajouter aussi dans `depends_on` du controller) et une entrée dans
  `inventories/local/hosts.yml` (voir le [runbook RB-03](runbooks.md#rb-03-ajouter-ou-retirer-un-serveur)).
- Les images occupent environ 1 Go sur l'hôte Docker (voir l'erreur n° 9 du
  [dépannage](troubleshooting.md)).

---

## ADR-04 — Rôle public `geerlingguy.nginx` 3.3.1 pour nginx, rôles maison pour le reste

**Contexte**

Les consignes autorisent les rôles publics Ansible Galaxy pour les rôles d'infrastructure
(`common`, `nginx`) et les **interdisent pour `fleetinfo`**. Tout rôle public doit être épinglé
dans `requirements.yml` et justifié : pourquoi ce rôle plutôt qu'un rôle maison, état de
maintenance, licence, compatibilité Debian 12, variables surchargées, risques identifiés.

**Décision**

- **Un seul rôle public** : `geerlingguy.nginx`, version `3.3.1` épinglée dans
  [`ansible/requirements.yml`](../ansible/requirements.yml). Il est déclaré comme
  **dépendance** de notre rôle `webserver`
  ([`roles/webserver/meta/main.yml`](../ansible/roles/webserver/meta/main.yml)) et s'exécute
  donc automatiquement juste avant lui.
- Partage des responsabilités :

| Responsabilité | Porté par |
|---|---|
| Paquet nginx (dépôts Debian), service démarré et activé, `/etc/nginx/nginx.conf` (validé par `nginx -t -c %s` avant d'être posé) | `geerlingguy.nginx` |
| Suppression du site `default` de Debian (`/etc/nginx/sites-enabled/default`) | `geerlingguy.nginx` (`nginx_remove_default_vhost: true`) |
| Site Fleet Info `/etc/nginx/sites-enabled/fleetinfo.conf`, `/health`, `/status` protégé, fichier htpasswd, chaîne de handlers | notre rôle `webserver` |
| Paquets de base, fuseau horaire, compte d'exploitation, bannière | notre rôle `common` (rôle maison) |
| Application Fleet Info | notre rôle `fleetinfo` (rôle maison, obligatoire) |

- Variables du rôle public surchargées (dans `roles/webserver/meta/main.yml`, bloc `vars` de la
  dépendance) :

| Variable | Défaut du rôle public (3.3.1) | Valeur du socle | Raison |
|---|---|---|---|
| `nginx_remove_default_vhost` | `false` | `true` | Le site `default` de Debian écoute lui aussi en `default_server` sur le port 80 : `nginx -t` échouerait (« duplicate default server »). |
| `nginx_vhosts` | `[]` | `[]` (explicite) | Le mécanisme de vhosts du rôle public n'est pas utilisé : notre site est un template de `webserver`, avec sa propre validation. |
| `nginx_server_tokens` | `"on"` | `"off"` | Masque la version de nginx dans les en-têtes HTTP et les pages d'erreur. |

- Collections (non soumises à la même règle, mais épinglées pour la même raison) :
  `google.cloud` 1.15.0 (plugin d'inventaire `google.cloud.gcp_compute`, obligatoire) et
  `community.general` 12.6.7 (modules `timezone` et `htpasswd`, sans équivalent dans
  `ansible.builtin`).

**Justification**

- **Pourquoi ce rôle plutôt qu'un rôle maison** : l'installation de nginx, la gestion du
  service et d'un `nginx.conf` validé avant écriture sont génériques et bien couvertes par un
  rôle très répandu ; le code maison se concentre sur ce qui est propre au socle (le site,
  `/status`, la validation de **notre** configuration).
- **Licence** : MIT (fichier `LICENSE` du dépôt, licence détectée par GitHub ; le
  `meta/main.yml` du rôle indique `license (BSD, MIT)`). Compatible avec un usage interne.
- **Compatibilité Debian 12** : le rôle déclare la plateforme `Debian` (`versions: all`),
  `min_ansible_version: 2.10`, et installe nginx depuis les dépôts Debian
  (`tasks/setup-Debian.yml`, module `apt`). Vérifié sur le banc local (Debian 12 bookworm) :
  premier passage complet, second passage `changed=0`.
- **État de maintenance** (constaté sur GitHub le 2026-11-03) : dépôt
  `geerlingguy/ansible-role-nginx` actif et non archivé, 3.3.1 est la **dernière** étiquette
  publiée (commit du 2026-08-10, correction de dépréciations Ansible), environ 900 étoiles et
  une dizaine de tickets ou demandes de fusion ouverts. Mainteneur : Jeff Geerling, auteur de
  nombreux rôles Galaxy de référence.

**Risques identifiés et mesures**

| Risque | Mesure |
|---|---|
| Le rôle utilise des noms de modules courts (pas de FQCN) et ne respecte pas le profil `production` d'`ansible-lint` | Exclu de l'analyse (`exclude_paths: roles/geerlingguy.nginx/` dans [`ansible/.ansible-lint`](../ansible/.ansible-lint)) : code tiers non maintenu par nous. |
| Redémarrage de nginx au premier passage (handler `restart nginx` notifié par la suppression du site `default`) | Sans impact : le serveur n'est pas encore en service à ce moment-là. C'est le seul redémarrage du socle (voir ADR-10). |
| Le template `nginx.conf.j2` du rôle public n'écrit **aucun** en-tête « Géré par Ansible » | Corrigé : `nginx_conf_template` (vars de la dépendance, `roles/webserver/meta/main.yml`) pointe vers l'enveloppe [`roles/webserver/templates/nginx.conf.j2`](../ansible/roles/webserver/templates/nginx.conf.j2), qui écrit l'en-tête puis inclut **tel quel** le template du rôle public (`{% include %}`) : contenu inchangé, aucune duplication. Vérifié le 2026-11-04 (`head -4 /etc/nginx/nginx.conf`, `nginx -t` OK, `changed=0` au second passage). |
| Le template de vhost du rôle écoute aussi en IPv6 (`nginx_listen_ipv6: true` par défaut) | Sans effet : `nginx_vhosts: []`, le template de vhost du rôle n'est jamais utilisé. Notre site n'écoute qu'en IPv4 (erreur n° 7 du dépannage). |
| Indisponibilité de Galaxy ou retrait de la version au moment de `ansible-galaxy install` | Version épinglée ; en entreprise, miroir interne (Automation Hub privé ou dépôt Git interne). |
| Changement de variables lors d'une montée de version majeure | Montée de version traitée comme un changement à part entière : relecture du changelog, test sur le banc local, `--check --diff`, second passage `changed=0`. |

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Rôle nginx entièrement maison | Plus de code à maintenir pour une partie générique (paquet, service, `nginx.conf`), sans bénéfice pour le socle. |
| Collection officielle `nginxinc.nginx_core` | Plus lourde et orientée vers les paquets nginx.org / NGINX Plus ; surdimensionnée pour un site statique servi depuis les dépôts Debian. |
| Utiliser `nginx_vhosts` du rôle public pour le site Fleet Info | Le site, `/status` et leur validation par `nginx -t` puis reload seraient hors de notre contrôle (template et handlers du rôle public). |
| Rôle public pour `common` | Le rôle est court et propre au socle ; un rôle public n'apporterait que des dépendances. |
| Rôle public pour `fleetinfo` | Interdit par les consignes. |

**Conséquences**

- Le rôle public doit être installé avant le premier `site.yml` (sinon :
  `the role 'geerlingguy.nginx' was not found`, voir l'erreur n° 20 du
  [dépannage](troubleshooting.md)) : l'entrypoint du controller s'en charge au démarrage ;
  `ansible-galaxy install -r requirements.yml` reste la commande de vérification ou de
  rattrapage.
- Le template `nginx.conf.j2` du rôle public n'écrit pas d'en-tête : le socle le surcharge par
  une enveloppe (`nginx_conf_template`, voir le tableau des risques ci-dessus).
- Le rôle `webserver` ne peut pas être joué sans `geerlingguy.nginx` ; le tag `webserver`
  s'applique aussi à la dépendance (`--tags webserver` rejoue donc les deux).

---

## ADR-05 — State Terraform local

**Contexte**

Le projet GCP est fourni par un lab Google Skills et **supprimé à la fin de chaque session**.
Les consignes acceptent un state local mais demandent de documenter ce choix et ce qu'il
faudrait faire en entreprise.

**Décision**

- Aucun bloc `backend` : le state est stocké localement dans `terraform/terraform.tfstate`
  (et `terraform.tfstate.backup`), sur le poste de l'opérateur qui lance `terraform apply`.
- Le state et `terraform.tfvars` sont ignorés par Git (`.gitignore` racine et
  `socle-web-automatise/.gitignore`). Le fichier `.terraform.lock.hcl` est, lui, versionné.

**Justification**

- Un backend distant (bucket GCS) devrait vivre dans le projet du lab, donc disparaître avec
  lui, et être créé **avant** `terraform init` : complexité sans bénéfice pour un projet qui
  ne vit que le temps d'une session.
- Un seul opérateur applique les changements pendant une session de lab (démonstration,
  répétition générale) : le verrouillage n'apporte rien dans ce contexte.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Backend GCS dans le projet du lab | Bucket supprimé avec le projet ; création manuelle préalable à chaque session, hors IaC. |
| Backend GCS dans un projet personnel durable | Mélange des comptes personnels et étudiants ; droits croisés impossibles à obtenir sur un projet de lab. |
| Terraform Cloud / HCP Terraform | Compte et jeton supplémentaires à gérer pour un environnement éphémère. |

**Conséquences**

- Le state n'existe que sur **un** poste : seul cet opérateur peut modifier ou détruire
  l'infrastructure de la session. S'il est perdu, la fin du lab supprime de toute façon les
  ressources.
- Aucun verrouillage : ne jamais lancer deux `terraform apply` en parallèle.
- Le state contient en clair les valeurs marquées `sensitive` (IP de l'opérateur dans
  `ssh_source_ranges`), la clé publique et le `project_id` : il ne doit jamais être partagé ni
  versionné.
- Si une session s'est terminée **sans** `terraform destroy` (lab expiré), le state local
  référence des ressources d'un projet qui n'existe plus : il faut le supprimer avant la
  session suivante (procédure dans [lab-gcp.md](lab-gcp.md), section 9, et erreur n° 13 du
  [dépannage](troubleshooting.md)).

**Ce qu'il faudrait en entreprise**

| Besoin | Mise en œuvre recommandée |
|---|---|
| State partagé et durable | Backend `gcs` dans un **projet dédié** à l'outillage (distinct des projets applicatifs), bucket régional, accès uniforme au niveau du bucket, prévention de l'accès public. |
| Historique et restauration | **Versioning d'objets** activé sur le bucket, règle de cycle de vie sur les versions non courantes. |
| Concurrence | **Verrouillage natif** du backend `gcs` (fichier de verrou posé à chaque opération) ; aucun `apply` hors pipeline. |
| Confidentialité | Chiffrement **CMEK** (clé Cloud KMS, option `kms_encryption_key` du backend) ; IAM au moindre privilège : écriture réservée au compte de service de la CI, lecture restreinte. |
| Traçabilité | **CI/CD** : `fmt -check`, `validate`, `plan` sur chaque demande de fusion, `apply` après approbation ; journaux d'audit Cloud Audit Logs sur le bucket. |
| Isolation des environnements | Un state par environnement : **dossiers par environnement** (`envs/dev`, `envs/prod`, chacun avec son `prefix`) de préférence, ou **workspaces** Terraform pour des environnements strictement identiques. |

Exemple (non utilisé dans le lab) :

```hcl
terraform {
  backend "gcs" {
    bucket = "novaretail-tfstate"          # bucket du projet d'outillage, versioning activé
    prefix = "socle-web-automatise/prod"   # un préfixe par environnement
    # kms_encryption_key = "projects/<projet-outillage>/locations/<region>/keyRings/<anneau>/cryptoKeys/<cle>"
  }
}
```

Migration d'un state local existant vers ce backend : `terraform init -migrate-state`.

---

## ADR-06 — Accès SSH : clé de déploiement injectée par métadonnée, SSH limité à l'IP de l'opérateur

**Contexte**

Ansible se connecte aux VM en SSH depuis le controller, qui tourne sur le poste de
l'opérateur et sort sur Internet par l'IP publique de ce poste. Les consignes demandent : clé
publique injectée via les métadonnées de la VM (ou OS Login, à justifier), aucune clé privée
dans le dépôt, SSH ouvert **uniquement** aux plages nécessaires (à justifier), règles de
firewall ciblant les VM par tag réseau. Dans le lab, le compte, le projet et les droits IAM
changent à chaque session.

**Décision**

- **Clé de déploiement ed25519** générée sur le poste par
  [`local/scripts/generate-keys.sh`](../local/scripts/generate-keys.sh) :
  `local/ssh/fleet_key` (privée) et `local/ssh/fleet_key.pub` (publique), commentaire
  `fleetinfo-deploy`, jamais versionnées (`.gitignore`). La même clé sert en local et sur le
  cloud.
- **Injection par métadonnée d'instance** (module `compute`) :
  `ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"`, avec `ssh_user = "ansible"` et la clé
  lue depuis `ssh_public_key_path` (défaut `../local/ssh/fleet_key.pub`). L'agent invité GCE
  crée l'utilisateur `ansible`, sudoer sans mot de passe.
- **OS Login désactivé sur les VM** : métadonnée `enable-oslogin = "FALSE"` (variable de module
  `enable_os_login`, défaut `false`), qui prime sur une éventuelle activation au niveau du
  projet.
- **Firewall** (module `network`), deux règles ciblant le tag réseau `fleetinfo-web`
  (`network_tag`), jamais toutes les instances :
  - `fleetinfo-vpc-allow-ssh` : TCP `ssh_port` (22) depuis `ssh_source_ranges` uniquement ;
  - `fleetinfo-vpc-allow-http` : TCP `http_port` (80) depuis `http_source_ranges`
    (défaut `["0.0.0.0/0"]`).
- **`ssh_source_ranges` = IP publique du poste de l'opérateur en `/32`**
  (`curl -4 -s https://ifconfig.me`), variable **sans défaut**, `sensitive = true`, avec une
  validation : au moins une plage, uniquement des CIDR **IPv4** (les VM n'ont qu'une IP publique
  IPv4) de préfixe **`/16` minimum**. Sont donc refusés `0.0.0.0/0`, ses contournements
  (`0.0.0.0/1` + `128.0.0.0/1`, `203.0.113.10/0`) et l'IPv6 (vérifié le 2026-11-04).

**Justification**

- **Métadonnées plutôt qu'OS Login** : fonctionne avec n'importe quel compte de lab sans
  attribution de rôles IAM supplémentaires ; l'utilisateur SSH reste `ansible` à chaque
  session, ce qui garde `ansible_user: ansible` constant dans
  `inventories/cloud/group_vars/all.yml`. Avec OS Login, le nom d'utilisateur POSIX est
  dérivé du compte étudiant, donc différent à chaque session.
- **Plage SSH = IP de l'opérateur en `/32`** : toutes les connexions SSH légitimes partent du
  controller, qui sort sur Internet par l'IP publique du poste. Aucune autre source n'a
  besoin du port 22 : le fermer au reste d'Internet supprime l'exposition aux scans et aux
  tentatives de force brute. L'IP est une donnée personnelle : `sensitive = true` la masque
  dans `plan`/`apply` (`(sensitive value)`) et dans les journaux d'une future CI.
- **Clé générée hors Terraform** : aucune clé privée ne transite par Terraform ni par son
  state.
- Vérifié (plan hors ligne) : `source_ranges` de la règle SSH affiché `(sensitive value)` ;
  `0.0.0.0/0` refusé par la validation.

**Alternatives écartées**

| Alternative | Avantages | Raison du rejet dans ce projet |
|---|---|---|
| **OS Login** | Accès lié à l'identité IAM, révocation centralisée, audit | Dépend des rôles IAM accordés au compte de lab (`roles/compute.osAdminLogin` pour `sudo`) ; nom d'utilisateur différent à chaque session ; clé à enregistrer (`gcloud compute os-login ssh-keys add`) à chaque session. **Solution recommandée en entreprise.** |
| **IAP TCP forwarding** (source `35.235.240.0/20`) | Aucun port 22 exposé sur Internet, VM possiblement sans IP publique | Exige `roles/iap.tunnelResourceAccessor`, l'API IAP, et `gcloud` dans le controller (ProxyCommand `gcloud compute start-iap-tunnel`) : plus de dépendances et d'authentification dans le conteneur ; disponibilité non garantie dans le lab. |
| Clé générée par Terraform (`tls_private_key`) | Pas de script à lancer | La clé **privée** serait stockée en clair dans le state Terraform. |
| Clé dans les métadonnées **du projet** | Une seule clé pour toutes les VM | Touche toutes les VM du projet, au-delà du périmètre du socle. |
| SSH ouvert à `0.0.0.0/0` | Simple, insensible au changement d'IP | Exposition inutile ; refusé par la validation de `ssh_source_ranges`. |
| Bastion | Point d'entrée unique et journalisé | VM supplémentaire à créer et durcir, temps de lab consommé. |

**Conséquences**

- Si l'IP publique du poste change (autre réseau, VPN, partage de connexion), SSH expire :
  mettre à jour `ssh_source_ranges` dans `terraform.tfvars` puis `terraform apply` (mise à
  jour en place de la seule règle `fleetinfo-vpc-allow-ssh`). Voir l'erreur n° 8 du
  [dépannage](troubleshooting.md).
- Un seul opérateur à la fois peut piloter les VM, sauf à ajouter les IP de ses collègues
  dans `ssh_source_ranges`.
- Si une politique d'organisation impose OS Login (`constraints/compute.requireOsLogin`), la
  métadonnée `ssh-keys` est ignorée : il faudrait basculer sur OS Login (point à relever lors
  de la première session, voir [lab-gcp.md](lab-gcp.md)).
- **Dette technique** : même clé pour le local et le cloud ; en entreprise, une clé par
  environnement (ou OS Login) et une rotation planifiée.
- Rotation de la clé : supprimer `local/ssh/`, relancer `local/scripts/generate-keys.sh`, puis
  (depuis `local/`) `docker compose up -d --build --wait` pour reconstruire les nœuds avec la
  nouvelle clé publique **et** `docker compose restart controller` : l'image du controller ne
  change pas, il n'est donc pas recréé et garde l'ancienne clé privée dans
  `/root/.ssh/fleet_key` tant que son entrypoint n'a pas été rejoué. Côté cloud :
  `terraform -chdir=terraform apply` (mise à jour en place de la métadonnée `ssh-keys`).

---

## ADR-07 — Inventaire dynamique `google.cloud.gcp_compute`

**Contexte**

Les consignes imposent un inventaire dynamique `inventories/cloud/<nom>.gcp.yml` utilisant le
plugin `google.cloud.gcp_compute` : sélection des VM par filtre sur les labels ou le tag
réseau (aucune IP écrite à la main), `compose` pour `ansible_host`, `keyed_groups` ou `groups`
produisant les mêmes noms de groupes qu'en local, et `project_id` jamais écrit dans un fichier
versionné.

**Décision**

Modèle versionné [`inventories/cloud/fleet.gcp.yml.example`](../ansible/inventories/cloud/fleet.gcp.yml.example) :

| Option | Valeur | Rôle |
|---|---|---|
| `plugin` | `google.cloud.gcp_compute` | Plugin d'inventaire (activé dans `[inventory] enable_plugins` de `ansible.cfg`, reconnu grâce au suffixe `.gcp.yml`). |
| `projects` | `__GCP_PROJECT_ID__` (remplacé à la génération) | Projet de la session. |
| `auth_kind` | `application` | Application Default Credentials (ADC). |
| `filters` | `labels.app = fleetinfo` et `status = RUNNING` | Seules les VM du socle, démarrées. |
| `hostnames` | `name` | Nom d'hôte Ansible = nom de la VM (`fleetinfo-web-1`…). |
| `vars_prefix` | `gce_` | Données de l'API exposées en `gce_zone`, `gce_machineType`, `gce_labels`… |
| `compose` | `ansible_host: networkInterfaces[0].accessConfigs[0].natIP` ; `ansible_user: metadata['ssh-keys'].split(':')[0]` | Connexion par l'IP publique éphémère, avec l'utilisateur déduit de la métadonnée `ssh-keys` posée par Terraform (aligné sur `ssh_user` sans être recopié ; repli `ansible_user: ansible` du `group_vars` cloud, qui porte aussi la clé privée et les options SSH). Vérifié avec une réponse d'API simulée : `opsuser:...` donne `ansible_user: opsuser`. |
| `keyed_groups` | `labels.role` (préfixe et séparateur vides) → `web` ; `labels.env` (préfixe `env`) → `env_cloud` ; `zone` (préfixe `zone`) → `zone_<zone>` (ex. `zone_us_central1_f`) | Même groupe `web` qu'en local, plus des groupes de ciblage ponctuel. |

- Le vrai fichier `inventories/cloud/fleet.gcp.yml` (ignoré par Git) est **généré** sur le
  poste après `terraform apply` par
  [`scripts/prepare-cloud-inventory.sh`](../scripts/prepare-cloud-inventory.sh), qui :
  1. injecte `terraform -chdir=terraform output -raw project_id` (ou le projet passé en
     argument), après contrôle du format ;
  2. copie les ADC de `gcloud` dans `.secrets/gcp-adc.json` (droits `600`, ignoré par Git),
     lues par le controller via `GOOGLE_APPLICATION_CREDENTIALS`.
- Les labels sont posés par Terraform (`terraform/locals.tf`) : `app`, `env`, `role`, `team`.

**Justification**

- L'option `projects` du plugin n'a **pas** de variable d'environnement équivalente : générer
  le fichier à partir d'un modèle versionné est le seul moyen de ne jamais versionner le
  `project_id` d'une session, tout en gardant un fichier lisible et relu.
- Les labels servent à la fois au filtre (`app`) et aux groupes (`role`, `env`) : une seule
  source de vérité, posée par Terraform. Le filtre `status = RUNNING` évite de tenter de
  configurer une VM arrêtée ou en cours de création.
- `auth_kind: application` réutilise la connexion `gcloud` de l'opérateur : aucune clé de
  compte de service à créer, stocker ou distribuer.
- Le plugin réduit `zone` et `machineType` à leur nom court (`us-central1-f`, `e2-small`) :
  ces valeurs s'affichent telles quelles sur la page.
- Vérifié avec le vrai plugin `google.cloud` 1.15.0 sur une réponse **simulée** de l'API
  Compute Engine : `--graph` donne `@web`, `@env_cloud`, `@zone_us_central1_f` ; filtre envoyé
  à l'API `(labels.app = fleetinfo) (status = RUNNING)` ; `ansible_host` = `natIP`,
  `gce_machineType` = nom court du type. **Pas encore exécuté sur un vrai projet** (voir
  [lab-gcp.md](lab-gcp.md)).

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Inventaire statique généré depuis `terraform output` | Ne répond pas à l'exigence d'inventaire dynamique ; à régénérer à chaque changement d'IP. |
| Filtre sur le tag réseau (`tags.items`) | Possible, mais le label `app` sert aussi aux groupes et offre une syntaxe de filtre plus simple. |
| `auth_kind: serviceaccount` avec une clé JSON | Clé longue durée à créer et protéger ; la création de clés peut être interdite dans le lab. |
| `hostnames` sur l'IP publique | Moins lisible dans `--graph`, les journaux et `deploy.log` ; change à chaque session. |
| `ansible_host` = IP interne | Injoignable depuis le poste (pas de VPN ni de bastion). |

**Conséquences**

- `scripts/prepare-cloud-inventory.sh` doit être relancé à **chaque** session (nouveau
  `project_id`, nouvelles ADC).
- Une VM arrêtée disparaît de l'inventaire : elle n'est ni configurée ni mise à jour.
- Passer de 2 à 3 VM côté Terraform suffit : la troisième apparaît dans `web` sans modifier
  le code Ansible.
- **Dette technique** : les ADC de l'utilisateur sont copiées dans `.secrets/` ; en
  entreprise, utiliser un compte de service dédié en lecture seule (`roles/compute.viewer`),
  idéalement par emprunt d'identité plutôt que par clé.

---

## ADR-08 — Déploiement applicatif par releases, contrôle de santé, retour arrière et canari

**Contexte**

L'incident à l'origine du projet est une mise en production ratée, sans retour arrière. Les
consignes exigent : une release par répertoire, un lien `current`, un `block`/`rescue`/`always`
avec vérification de `/health` (module `ansible.builtin.uri`), un retour automatique à N-1, un
journal de déploiement et un moyen documenté de provoquer un échec.

**Décision**

Rôle [`fleetinfo`](../ansible/roles/fleetinfo/) (écrit par l'équipe), fichier principal
[`tasks/deploy.yml`](../ansible/roles/fleetinfo/tasks/deploy.yml) :

- **Arborescence** : `/opt/fleetinfo/releases/<version>/` (`index.html`, `health.json`) et
  lien `/opt/fleetinfo/current` vers la release active, servi comme racine par nginx
  (`webserver_document_root`).
- **Avant la bascule** : lecture du lien `current` (`stat`, `lnk_source`) pour mémoriser la
  release active, cible d'un retour arrière.
- **`block`** : création de la release, génération de `index.html` et `health.json`, bascule
  **atomique** du lien (`ansible.builtin.file`, `state: link`), interrogation de
  `fleetinfo_health_url` (`http://127.0.0.1:80/health`) jusqu'à obtenir HTTP 200 et la
  version attendue (`fleetinfo_health_retries: 5`, `fleetinfo_health_delay: 2`), contrôle
  `status == 'ok'`, mise à jour du fait local `/etc/ansible/facts.d/fleetinfo.fact`.
- **`rescue`** : rebascule de `current` vers la release précédente, rechargement immédiat de
  nginx, revérification de `/health` avec la version précédente (dans un bloc imbriqué
  `block`/`rescue` : si N-1 ne répond pas non plus, le statut reste `ECHEC_ROLLBACK_KO` et le
  message final demande une intervention manuelle, vérifié le 2026-11-04), puis **échec explicite**
  (`ansible.builtin.fail`) avec la cause et l'emplacement du journal.
- **`always`** : une ligne par tentative réelle dans `/var/log/fleetinfo/deploy.log` (format
  détaillé dans le [dépannage](troubleshooting.md), section 1.1).
- **Canari** (play « Déployer l'application Fleet Info » de `site.yml`) :
  `serial: [1, "100%"]` et `max_fail_percentage: 0` : un premier serveur seul, puis tous les
  autres ensemble ; au premier échec, le play s'arrête.
- **Ménage** ([`tasks/cleanup.yml`](../ansible/roles/fleetinfo/tasks/cleanup.yml)) :
  conservation de `fleetinfo_keep_releases: 3` releases ; la release active et la précédente
  ne sont jamais supprimées.
- **Démonstration d'échec** : `-e fleetinfo_simulate_failure=true` produit une release sans
  `health.json` (nginx répond 404 sur `/health`). Un garde-fou refuse la simulation sur la
  version déjà active (il n'y aurait rien vers quoi revenir).
- **Retour arrière manuel** : [`rollback.yml`](../ansible/rollback.yml) appelle
  `tasks/rollback.yml`, qui réutilise `tasks/deploy.yml` sans régénérer la release
  (`fleetinfo_render_release: false`, `fleetinfo_deploy_kind: rollback-manuel`), après avoir
  vérifié que la release cible existe et contient `health.json`.

**Justification**

- La bascule d'un lien symbolique (lien temporaire puis renommage) est atomique et
  instantanée : nginx sert soit l'ancienne release, soit la nouvelle, jamais un mélange.
  nginx résolvant le lien à chaque requête (pas d'`open_file_cache`), aucun rechargement n'est
  nécessaire pour servir la nouvelle version.
- Le contrôle de santé est fait **depuis le serveur lui-même** (`127.0.0.1`, à travers
  nginx) : il est indépendant du firewall, de l'IP publique et du port publié (8081/8082 en
  local, 80 sur GCP), donc identique dans les deux environnements.
- Le contrôle porte sur le **contenu** (`status` et `version`), pas seulement sur le code
  HTTP : une ancienne release encore servie serait détectée.
- Le rechargement de nginx du `rescue` est une tâche et non un handler : il doit avoir lieu
  **immédiatement**, avant la revérification (un handler s'exécuterait en fin de play).
- Le canari limite l'impact d'une release défectueuse à un seul serveur, qui revient
  lui-même à N-1 : le parc reste homogène en N-1.
- Vérifié sur le banc local : déploiement 1.1.0 (`/health` en 1.1.0 sur les deux nœuds) ;
  échec simulé de 1.2.0 (`/health` en 404 sur 6 appels (1 + 5 nouvelles tentatives), rescue vers 1.1.0, `node1` :
  `failed=1 rescued=1`, `node2` jamais touché, site en ligne en 1.1.0) ; puis 1.2.0 saine
  déployée normalement ; `rollback.yml` vers 1.1.0 puis retour vers 1.2.0 ; ménage d'une
  4e release (1.3.0) qui supprime 1.0.0.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Écraser les fichiers en place | Aucun retour arrière possible, état intermédiaire visible pendant l'écriture. |
| Retour arrière par redéploiement de la version N-1 (régénération) | Plus lent, et le contenu restauré ne serait pas exactement celui qui tournait ; `rollback.yml` rebascule sur la release présente sur disque. |
| Paquet `.deb` ou image de conteneur publiés dans un dépôt d'artefacts | Pertinent pour une vraie application ; disproportionné pour une page générée sur chaque serveur à partir de ses facts. |
| Handler pour le rechargement du `rescue` | Exécuté trop tard (fin de play), après la revérification. |
| Déploiement de tous les serveurs en même temps (`serial` absent) | Une release défectueuse toucherait tout le parc simultanément. |
| Bleu/vert derrière un load balancer | Pas de load balancer dans le périmètre (voir les limites connues). |

**Conséquences**

- Valeurs possibles de `resultat` dans le journal : `SUCCES`, `ECHEC_ROLLBACK_OK`,
  `ECHEC_ROLLBACK_KO`, `ECHEC_SANS_ROLLBACK` ; valeurs de `type` : `deploiement`,
  `rollback-manuel`, `mise-a-jour-sur-place`.
- **Premier déploiement en échec** : aucune version vers laquelle revenir
  (`ECHEC_SANS_ROLLBACK`) ; le lien `current` reste sur la release défaillante.
- **Mise à jour sur place** (même version, contenu régénéré, par exemple après un changement
  de variable d'affichage) : pas de bascule, donc pas de cible de retour arrière si elle
  échoue.
- Après un retour arrière manuel, aligner `fleetinfo_version` dans
  `group_vars/all/vars.yml` sur la version restaurée, sinon le prochain `site.yml`
  redéploierait la version quittée.
- `rollback.yml` sans argument fait l'aller-retour entre les deux dernières releases ; la page
  restaurée affiche la date de son déploiement initial (elle n'est pas régénérée). Le
  `site.yml` suivant, version réalignée, la régénère une fois sur place (`changed=3`, ligne
  `type=mise-a-jour-sur-place`), puis `changed=0` (observé le 2026-11-04).
- `rollback.yml` refuse `-e fleetinfo_version` (les extra vars détourneraient la bascule vers une
  release non vérifiée) : la cible se choisit avec `-e fleetinfo_rollback_version`.
- En `--check`, la bascule est simulée (`force: "{{ ansible_check_mode }}"`) et le contrôle de
  santé est sauté : `--check --diff` annonce les changements sans erreur (vérifié).

---

## ADR-09 — Plays écrits dans `site.yml` (pas de dossier `playbooks/`)

**Contexte**

La structure suggérée par les consignes prévoit un dossier `ansible/playbooks/` importé par
`site.yml`. Le socle s'appuie sur des `group_vars` **de playbook** (`ansible/group_vars/all/`,
qui contient `vars.yml` et le coffre `vault.yml`), chargés quel que soit l'inventaire.

**Décision**

- Les trois plays (`common`, `webserver`, `fleetinfo`) sont écrits **directement** dans
  [`ansible/site.yml`](../ansible/site.yml), un play par couche, chacun limité à l'appel d'un
  rôle avec son tag.
- [`ansible/rollback.yml`](../ansible/rollback.yml) est rangé à côté de `site.yml` pour la même
  raison.
- Il n'existe **pas** de dossier `ansible/playbooks/`.

**Justification**

- Ansible charge les `group_vars` de playbook relativement au dossier **du playbook joué**.
  Avec des plays importés depuis `playbooks/`, `ansible/group_vars/all/` n'était pas chargé :
  variable `vault_webserver_status_password` indéfinie, rôle `webserver` en échec. Le réglage
  `playbook_vars_root` (valeurs `top`, `bottom`, `all`) a été testé sans résoudre le problème.
- Un play par couche a un effet voulu : les handlers du play `webserver` (validation puis
  rechargement de nginx) s'exécutent à la fin de ce play, donc **avant** le déploiement
  applicatif.
- Les plays restent courts : toute la logique est dans les rôles, conformément aux consignes.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Déplacer `group_vars/all/` dans chaque inventaire | Duplique les variables communes et le coffre dans `local` et `cloud` : divergence assurée. |
| Ranger `group_vars/` dans `playbooks/` | Ne serait plus chargé pour `site.yml` et `rollback.yml` à la racine ; structure trompeuse. |
| Lien symbolique `playbooks/group_vars` vers `../group_vars` | Fragile sous Windows (liens symboliques non créés par Git par défaut) ; comportement implicite difficile à expliquer au run. |
| `vars_files` explicites dans chaque play | Change la précédence : les `vars_files` de play l'emportent sur **toutes** les variables d'inventaire (`group_vars` d'inventaire, y compris ceux d'un groupe précis, et `host_vars`), ce qui interdirait de surcharger une valeur commune pour un groupe ou un hôte ; et la déclaration se répète dans chaque play. |

**Conséquences**

- Écart assumé avec la structure suggérée, expliqué dans le [README](../README.md).
- Tout nouveau playbook doit être placé dans `ansible/`, à côté de `site.yml`, pour bénéficier
  des variables communes et du coffre (erreur n° 1 du [dépannage](troubleshooting.md)).

---

## ADR-10 — Validation de la configuration nginx par une chaîne de handlers, reload plutôt que restart

**Contexte**

Les consignes exigent des handlers aux noms explicites, qu'une configuration nginx soit
validée (`nginx -t`) avant d'être rechargée, qu'une configuration invalide ne soit jamais
appliquée, que `reloaded` soit préféré à `restarted` et que les handlers ne s'exécutent que si
quelque chose a changé.

**Décision**

Dans [`roles/webserver`](../ansible/roles/webserver/) :

0. **Avant écriture**, la tâche « Déployer la configuration du site Fleet Info » (template
   `fleetinfo.conf.j2` vers `/etc/nginx/sites-enabled/fleetinfo.conf`) teste le fichier
   **candidat** par son option `validate:` : un `sh -c` écrit une configuration minimale
   temporaire (`events {} http { include /etc/nginx/mime.types; include <candidat>; }`) et
   lance `nginx -t -q -c` dessus. Si le test échoue, la tâche échoue, le fichier en place n'est
   **pas** remplacé et aucun handler n'est notifié.
1. Si le fichier a changé, la tâche notifie **« Valider la configuration nginx »**.
2. Ce handler exécute `nginx -t` (`ansible.builtin.command`, `changed_when: true`) et notifie
   **« Recharger nginx »**.
3. « Recharger nginx » fait `ansible.builtin.service` avec `state: reloaded`.

Si `nginx -t` (configuration **complète**) échoue malgré tout, le premier handler est en échec,
la chaîne s'arrête et le rechargement n'a jamais lieu : c'est le second garde-fou. Le fichier htpasswd ne notifie rien (nginx le relit à chaque requête
authentifiée). Les rôles `common` et `fleetinfo` n'ont pas de handler (voir ADR-08). Le seul
redémarrage du socle est le handler `restart nginx` de `geerlingguy.nginx`, au premier
passage, lors de la suppression du site `default`.

**Justification**

- Un `validate: nginx -t -c %s` direct ne convient pas à un fichier de site : testé **seul**,
  hors d'un contexte `http {}`, la directive `server` est refusée. D'où l'enveloppe minimale
  `events {} http { ... include %s; }` : le fichier candidat est validé dans un vrai contexte
  `http`, **avant** d'être écrit, donc une configuration invalide n'arrive jamais sur disque.
- La chaîne de handlers reste utile : elle valide la configuration **complète** (avec
  `nginx.conf` et tous les fichiers inclus) juste avant le rechargement.
- Un reload (SIGHUP) relit la configuration sans couper les connexions en cours ni
  interrompre le service ; il suffit pour tout ce que gère le rôle (site, port d'écoute,
  `/status`). Un restart couperait le service sans bénéfice.
- `changed_when: true` sur `nginx -t` est nécessaire pour notifier le handler suivant ; c'est
  sans effet sur l'idempotence puisque le handler ne s'exécute que si le fichier a changé.
- Vérifié sur le banc local : un changement ne touchant que la page
  (`-e fleetinfo_environment=demo`) ne déclenche aucun handler ; un changement de
  `webserver_status_allowed_networks` déclenche « Valider la configuration nginx » puis
  « Recharger nginx » ; `-e webserver_listen_port=99999` est refusé **avant écriture** par le
  `validate:` (`[emerg] invalid port in "99999" of the "listen" directive`), le fichier en place
  est inchangé, aucun handler ne s'exécute et le site reste en ligne ; `-e socle_http_port=8080`
  déclenche validation puis rechargement, `/health` répond sur 8080, et le retour au port 80
  fonctionne de même (2026-11-04) ; un second passage ne déclenche aucun handler.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| `validate: nginx -t -c %s` direct sur le template du site | Le fichier de site testé seul n'est pas une configuration nginx complète (voir ci-dessus) : remplacé par la validation dans une enveloppe minimale. |
| `state: restarted` | Coupe les connexions ; inutile pour une modification de configuration. |
| Valider dans une tâche plutôt qu'un handler | `nginx -t` serait exécuté à chaque passage, même sans changement. |

**Conséquences**

- Une configuration de site invalide n'est **jamais écrite** : la tâche échoue avec le message
  de `nginx -t`, le fichier précédent reste en place et nginx continue de servir. Corriger la
  variable puis relancer `ansible-playbook site.yml --tags webserver`.
- Limite résiduelle : l'enveloppe de validation ne contient pas les autres sites éventuels ;
  un conflit entre fichiers (deux `default_server` sur le même port, par exemple) n'est détecté
  que par le second garde-fou (handler), une fois le fichier écrit. Le socle n'a qu'un site.
- Les handlers s'exécutent à la fin du play `webserver` : un échec de `nginx -t` arrête l'hôte
  concerné avant le play de déploiement applicatif.

---

## ADR-11 — Gestion des secrets

**Contexte**

Aucun secret ne doit apparaître en clair dans le dépôt ni dans son historique. Le mot de passe
de la page `/status` doit être géré avec Ansible Vault (variables préfixées `vault_` et
référencées depuis un `vars.yml` en clair), les tâches qui manipulent un secret doivent porter
`no_log: true`, et les variables Terraform sensibles doivent être marquées `sensitive = true`.

**Décision**

- **Coffre Ansible Vault** :
  [`ansible/group_vars/all/vault.yml`](../ansible/group_vars/all/vault.yml), chiffré
  (`$ANSIBLE_VAULT;1.1;AES256`), contient `vault_webserver_status_password`. Le nom est
  référencé en clair dans `group_vars/all/vars.yml` :
  `webserver_status_password: "{{ vault_webserver_status_password }}"`.
- **Mot de passe du coffre** : fichier `socle-web-automatise/.vault_pass` (droits `600`,
  ignoré par Git via `.vault_pass*`), lu dans le controller par le script
  `/usr/local/bin/fleet-vault-pass` (`ANSIBLE_VAULT_PASSWORD_FILE`, ADR-02) et, hors controller,
  par `vault_password_file = ../.vault_pass` d'`ansible.cfg`. Il est transmis hors Git par l'équipe (section « Prérequis et accès » du
  [README](../README.md)).
- **`no_log: true`** sur la tâche « Créer le compte d'accès à la page /status »
  (`community.general.htpasswd`) ; `webserver_status_password` est déclaré `no_log: true` et
  `required: true` dans `roles/webserver/meta/argument_specs.yml`, sans valeur par défaut.
- **Mot de passe `/status`** : aléatoire, 24 caractères, compte `exploitation`
  (`webserver_status_user`), fichier `/etc/nginx/fleetinfo-status.htpasswd` (`root:www-data`,
  `0640`).
- **Hachage `apr_md5_crypt`** (`webserver_status_crypt_scheme`), vérifié nativement par nginx.
- **Terraform** : `ssh_source_ranges` est `sensitive = true` (racine et module `network`).
  Aucun autre secret côté Terraform : authentification par ADC, aucune clé de compte de
  service.
- **Fichiers ignorés par Git** : `.vault_pass*`, `.secrets/`, `local/ssh/`,
  `local/node/authorized_keys`, `ansible/inventories/cloud/fleet.gcp.yml`, state et
  `terraform.tfvars`.

**Justification**

- Le préfixe `vault_` et la référence dans `vars.yml` gardent chaque nom de variable lisible
  sans déchiffrer le coffre (exigence des consignes).
- `apr_md5_crypt` est vérifié par nginx sans coût CPU notable à chaque requête ; la robustesse
  repose sur un mot de passe long et aléatoire. `sha512_crypt` (nombreuses itérations) serait
  plus résistant à une attaque hors ligne mais coûterait du CPU à chaque requête authentifiée.
- Vérifié : `/status` répond 401 sans authentification, 401 avec un mauvais mot de passe,
  200 avec le bon (`stub_status`) ; une recherche du mot de passe dans le dépôt ne trouve
  aucune occurrence hors du `vault.yml` chiffré.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Google Secret Manager, HashiCorp Vault | Dépendance externe à provisionner à chaque session de lab éphémère ; disproportionné pour un secret. |
| SOPS | Outil supplémentaire dans le controller ; Ansible Vault est natif et demandé par les consignes. |
| `ansible-vault encrypt_string` dans `vars.yml` | Mélange clair et chiffré dans un même fichier ; moins lisible et plus difficile à faire tourner (`rekey`). |
| Mot de passe passé en `-e` ou en variable d'environnement | Non reproductible, visible dans l'historique du shell. |
| `sha512_crypt` | Voir la justification (coût CPU par requête). Reste disponible via `webserver_status_crypt_scheme`. |

**Conséquences**

- Le fichier `.vault_pass` est la clé de tous les secrets : quiconque le détient lit le coffre.
  À partager par un gestionnaire de mots de passe d'équipe, jamais par messagerie.
- Rotation du mot de passe `/status` : `ansible-vault edit group_vars/all/vault.yml` puis
  `ansible-playbook site.yml --tags webserver`. Rotation du mot de passe du coffre :
  `ansible-vault rekey --new-vault-password-file <nouveau fichier> group_vars/all/vault.yml`,
  puis remplacement de `../.vault_pass`. Détail : [RB-05](runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).
- `/status` passe en HTTP Basic sur HTTP : le mot de passe circule en clair sur le réseau tant
  que le TLS n'est pas en place (limite connue ; restreindre avec
  `webserver_status_allowed_networks` si nécessaire).
- `sensitive = true` masque l'affichage mais **pas** le stockage : la valeur reste lisible
  dans `terraform.tfvars` et dans le state (voir ADR-05).
- Un seul coffre, sans *vault IDs* : suffisant pour un secret ; à revoir si les secrets se
  multiplient ou diffèrent selon l'environnement.

---

## ADR-12 — Terraform en modules locaux, `count` et validations de variables

**Contexte**

Les consignes Terraform demandent : réseau, sous-réseau et VM encapsulés dans des modules
locaux (`modules/`), un `main.tf` racine limité à l'instanciation des modules, des variables
typées et documentées, des versions épinglées dans un unique `versions.tf`, un nombre de VM
paramétrable par une seule variable.

**Décision**

- **Deux modules locaux** :
  - [`modules/network`](../terraform/modules/network/) : VPC en mode *custom*
    (`auto_create_subnetworks = false`), sous-réseau, règles de firewall HTTP et SSH ciblant
    le tag réseau ;
  - [`modules/compute`](../terraform/modules/compute/) : VM Debian 12 en nombre paramétrable,
    labels, tag réseau, métadonnées `ssh-keys` et `enable-oslogin`, IP publique éphémère
    (`access_config {}`), aucun `startup-script`.
- [`main.tf`](../terraform/main.tf) n'instancie que les deux modules et relie
  `module.network.subnet_id` à l'entrée `subnetwork_id` du module `compute`. Les valeurs
  calculées (labels, contenu de la clé publique) sont dans `locals.tf`.
- **`count`** pour les VM (`instance_count = var.vm_count`), noms
  `format("%s-%d", var.name_prefix, count.index + 1)` → `fleetinfo-web-1`, `fleetinfo-web-2`…
- **Validations de variables** (`variables.tf`) : format de `project_id`, `zone` appartenant à
  `region`, `vm_count` entier entre 2 et 10, `ssh_source_ranges` (CIDR IPv4 de préfixe
  `/16` minimum : `0.0.0.0/0` et l'IPv6 refusés), `name_prefix`, `subnet_cidr`, existence de `ssh_public_key_path` ; dans le
  module `compute`, présence des labels `env`, `role`, `team`.
- **Versions** : `required_version = "~> 1.9"` et provider `hashicorp/google` `~> 8.9` dans
  [`versions.tf`](../terraform/versions.tf) uniquement ; configuration du provider dans
  `providers.tf` ; `.terraform.lock.hcl` versionné (google 8.9.0, empreintes pour plusieurs
  plateformes).

**Justification**

- Modules : une responsabilité par module, réutilisables indépendamment (aucune référence à
  une ressource d'un autre module) ; exigé par [TERRAFORM.md](../../TERRAFORM.md).
- `count` : les VM sont **identiques et interchangeables** ; passer de 2 à 3 VM ne demande que
  de modifier `vm_count`. C'est la forme la plus simple qui réponde au besoin.
- Les validations arrêtent les erreurs au `plan`, avec un message explicite, avant tout appel
  à l'API. La validation de la zone référence une autre variable (`var.region`), possibilité
  apparue avec Terraform 1.9, d'où `required_version = "~> 1.9"`.
- Lock file multi-plateformes : `terraform init` vérifie le même binaire de provider sous
  Windows, macOS et Linux.
- Vérifié : `terraform fmt -check -recursive`, `terraform init` et `terraform validate` sans
  erreur ; plan hors ligne `Plan: 6 to add` (VPC, sous-réseau, 2 règles de firewall, 2 VM),
  `source_ranges` de la règle SSH affiché `(sensitive value)` ; refus testés de `0.0.0.0/0`
  en SSH, d'une zone hors région et de `vm_count = 0`.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| Fichiers plats `network.tf` / `compute.tf` à la racine (structure suggérée par le README des consignes) | `TERRAFORM.md` impose des modules locaux ; la structure retenue l'emporte et est expliquée dans le README. |
| `for_each` sur une map de VM | Préférable quand chaque VM a une identité propre (supprimer une VM « du milieu ») ; ici les VM sont identiques, `count` est plus simple. |
| Modules publics `terraform-google-modules` | Dépendances externes plus lourdes, nombreuses options inutiles ici ; moins lisible pour la reprise. |
| Groupe d'instances géré (MIG) et modèle d'instance | Pertinent avec un load balancer et de l'autoréparation ; hors périmètre, et noms ou IP moins prévisibles pour l'exploitation. |
| `startup-script` pour installer nginx | Contraire à la frontière Terraform / Ansible : Terraform crée, Ansible configure. |

**Conséquences**

- Réduire `vm_count` supprime les VM de plus fort indice (`fleetinfo-web-3`, puis `-2`…).
- `allow_stopping_for_update = true` : changer `machine_type` arrête puis redémarre la VM ;
  l'IP publique éphémère peut alors changer. L'inventaire dynamique suit automatiquement ;
  les URL sont à relire avec `terraform -chdir=terraform output fleetinfo_urls`. Si la nouvelle
  IP a déjà servi à une autre VM, voir l'erreur n° 8a du [dépannage](troubleshooting.md)
  (« REMOTE HOST IDENTIFICATION HAS CHANGED »).
- La validation `fileexists(var.ssh_public_key_path)` s'applique à **toutes** les commandes,
  `destroy` compris : la clé publique doit rester présente tant que l'infrastructure existe.
- `required_providers` n'apparaît qu'une fois dans le dépôt (`versions.tf`).

---

## ADR-13 — Idempotence de la page : date de déploiement mémorisée dans un fait local

**Contexte**

La page d'accueil doit afficher « la date et l'heure du dernier déploiement », et un second
`ansible-playbook site.yml` doit afficher `changed=0`. Un template qui affiche une valeur
changeant à chaque exécution (heure courante, uptime, charge, espace libre) serait réécrit à
chaque passage.

**Décision**

- La date du dernier déploiement, la version active et la version précédente sont mémorisées
  dans le **fait local** `/etc/ansible/facts.d/fleetinfo.fact` (template
  `fleetinfo.fact.j2`, JSON), relu automatiquement à chaque collecte des facts sous
  `ansible_local.fleetinfo`.
- Dans `tasks/deploy.yml`, `fleetinfo_deployed_at` vaut la date de la collecte des facts
  (`ansible_facts.date_time.iso8601`) **uniquement** si `current` bascule ; sinon, la date
  mémorisée (`ansible_local.fleetinfo.deployed_at`). Même logique pour la version précédente
  (`fleetinfo_recorded_previous`).
- Le template `index.html.j2` n'affiche que des valeurs **stables** : pas d'heure courante,
  d'uptime, de charge ni d'espace libre (règle écrite en tête du template).
- Le texte `ansible_managed` (dans `ansible.cfg`) ne contient ni date ni chemin absolu.
- Le journal `deploy.log` n'est écrit que pour une tentative réelle (fichier généré, lien
  basculé ou échec).

**Justification**

- Le fait local est propre à chaque serveur, survit aux exécutions et est relu sans tâche
  supplémentaire (`gathering = smart`).
- La date est ainsi exacte (celle de la bascule) et stable entre deux déploiements.
- Vérifié : second passage `changed=0` sur les deux nœuds (`ok=39 changed=0 failed=0`) ;
  `--tags common` rejoué seul : `changed=0`.

**Alternatives écartées**

| Alternative | Raison du rejet |
|---|---|
| `ansible_facts.date_time` à chaque passage | La page changerait à chaque exécution : `changed=0` impossible. |
| Date de modification du répertoire de release (`stat`) | Tâche supplémentaire, et la date change si la release est régénérée sur place. |
| Lecture de la dernière ligne de `deploy.log` | Analyse de texte fragile ; le journal sert à l'audit, pas à porter l'état. |
| État stocké sur le controller | Non lié au serveur, perdu avec le conteneur, différent selon l'opérateur. |

**Conséquences**

- Supprimer `/etc/ansible/facts.d/fleetinfo.fact` sur un serveur fait afficher, au passage
  suivant, la date de ce passage (la page change une fois, puis redevient stable).
- Toute nouvelle information ajoutée à la page doit être stable d'une exécution à l'autre ;
  sinon, l'idempotence est perdue (voir l'erreur n° 10 du [dépannage](troubleshooting.md)).
- Après `rollback.yml`, la page restaurée garde la date de son déploiement initial (la release
  n'est pas régénérée), alors que le fait local enregistre la date de la bascule. Le premier
  `site.yml` qui suit (avec `fleetinfo_version` alignée sur la version restaurée) régénère
  donc une fois la page avec cette date (`type=mise-a-jour-sur-place` dans le journal),
  puis la page redevient stable (`changed=3` puis `changed=0`, observé le 2026-11-04).
