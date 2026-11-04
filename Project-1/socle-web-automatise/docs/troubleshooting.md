# Où regarder en cas de problème

Guide de diagnostic du « Socle Web Automatisé », pour l'équipe qui reprend le run.

- [1. Journaux](#1-journaux)
- [2. Fichiers générés sur les serveurs](#2-fichiers-générés-sur-les-serveurs)
- [3. Commandes de diagnostic](#3-commandes-de-diagnostic)
- [4. Erreurs déjà rencontrées et leur solution](#4-erreurs-déjà-rencontrées-et-leur-solution)
- [5. Arbre de décision : la page ne s'affiche pas](#5-arbre-de-décision--la-page-ne-saffiche-pas)

Documents liés : [README du socle](../README.md), [runbooks](runbooks.md),
[décisions techniques](decisions.md), [référence des variables](variables.md),
[contraintes du lab GCP](lab-gcp.md).

**Conventions**

- **(poste)** : terminal du poste de l'opérateur, depuis `Project-1/socle-web-automatise/`
  (sauf mention `cd local`).
- **(controller)** : shell du conteneur controller (`cd local && docker compose exec controller bash`),
  qui démarre dans `/workspace/ansible`. Pour le cloud, ajouter
  `-i inventories/cloud/fleet.gcp.yml` aux commandes `ansible*`.
- **(serveur)** : shell sur un nœud local ou une VM :
  - nœud local (poste, depuis `local/`) : `docker compose exec node1 bash` (shell `root`,
    `sudo` facultatif) ;
  - VM GCP (controller) : `ssh -i /root/.ssh/fleet_key ansible@<IP>` ; ou depuis le poste
    Linux/macOS/WSL : `ssh -i local/ssh/fleet_key ansible@<IP>`. Préfixer par `sudo` les
    commandes qui lisent les journaux ou la configuration.
- `<IP>`, `<ZONE>`, `<PROJECT_ID>` sont à remplacer (exemples : `203.0.113.10`,
  `us-central1-f`, `qwiklabs-gcp-00-0123456789ab`).
- **Statut des sorties** : seules les sorties signalées « observée » ont été relevées sur le
  banc local (2026-11-03). Les autres sont des **résultats attendus** ou des formes
  construites à partir du code. Le cloud n'a pas encore été exécuté sur un vrai projet GCP :
  aucune sortie cloud de ce document n'est une sortie observée.

---

## 1. Journaux

### 1.1 Journal de déploiement : `/var/log/fleetinfo/deploy.log`

Écrit par la section `always` du déploiement (rôle `fleetinfo`, tâche « Tracer la tentative de
déploiement dans le journal »), sur **chaque serveur**. Une ligne par **tentative réelle** :
un passage sur un serveur déjà conforme (rien de généré, rien de basculé, aucun échec)
n'écrit rien. `rollback.yml` y écrit aussi (même tâche).

- Droits : fichier `root:adm` `0640`, répertoire `/var/log/fleetinfo` `root:adm` `0750`
  (`fleetinfo_log_group: adm`). Le compte d'exploitation `fleetops` (groupe `adm`) peut le lire
  sans `sudo` ; l'utilisateur `ansible` doit utiliser `sudo`.
- Dates en **UTC** (suffixe `Z`). Les journaux nginx sont, eux, en heure locale du serveur
  (`Europe/Paris`, variable `common_timezone`) : en tenir compte pour corréler.

**Format** (construit par la tâche, une ligne par tentative) :

```text
<date UTC ISO 8601> hote=<inventory_hostname> type=<type> demandee=<version> precedente=<version|aucune> resultat=<résultat>[ detail="<tâche en échec> : <message>"]
```

| Champ | Valeurs | Signification |
|---|---|---|
| `hote` | `node1`, `fleetinfo-web-1`… | Nom d'hôte Ansible (nom du conteneur local ou de la VM). |
| `type` | `deploiement` | `site.yml` a basculé `current` vers une autre release. |
| | `rollback-manuel` | `rollback.yml` a rebasculé vers une release déjà présente. |
| | `mise-a-jour-sur-place` | La version demandée était déjà active ; ses fichiers ont été régénérés (par exemple après un changement de variable d'affichage). |
| `demandee` | `X.Y.Z` | Version demandée (`fleetinfo_version`, ou cible du retour arrière). |
| `precedente` | `X.Y.Z` ou `aucune` | Release active **avant** la tentative (égale à `demandee` pour une mise à jour sur place). |
| `resultat` | `SUCCES` | `/health` répond `status: ok` avec la version demandée. |
| | `ECHEC_ROLLBACK_OK` | Échec, retour automatique à `precedente` effectué **et vérifié** sur `/health`. Le site est en ligne en N-1. |
| | `ECHEC_ROLLBACK_KO` | Échec, et le retour arrière lui-même n'a pas pu être vérifié (`/health` ne répond pas avec la version précédente). **Site potentiellement hors service** : voir la [section 5](#5-arbre-de-décision--la-page-ne-saffiche-pas). |
| | `ECHEC_SANS_ROLLBACK` | Échec sans version vers laquelle revenir (premier déploiement, ou mise à jour sur place). |
| `detail` | texte | Présent en cas d'échec : nom de la tâche en échec, ` : `, message d'erreur ; sur une seule ligne, tronqué à 300 caractères, guillemets doubles remplacés par des simples. |

**Lignes observées** (banc local, 2026-11-03, `node1`) :

```text
2026-11-03T18:09:57Z hote=node1 type=deploiement demandee=1.1.0 precedente=1.0.0 resultat=SUCCES
2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
```

Lecture : livraison réussie de 1.1.0 (depuis 1.0.0), puis échec simulé de 1.2.0 (release sans
`health.json`, `/health` en 404 sur les 6 appels (1 + 5 nouvelles tentatives)) avec retour automatique, vérifié, à 1.1.0.

**Autres formes possibles** (construites à partir du code, dates et hôtes fictifs) :

```text
2026-11-03T18:30:00Z hote=node1 type=rollback-manuel demandee=1.1.0 precedente=1.2.0 resultat=SUCCES
2026-11-03T18:35:00Z hote=node1 type=mise-a-jour-sur-place demandee=1.1.0 precedente=1.1.0 resultat=SUCCES
2026-11-03T18:40:00Z hote=fleetinfo-web-1 type=deploiement demandee=1.0.0 precedente=aucune resultat=ECHEC_SANS_ROLLBACK detail="..."
```

**Lire le journal**

```bash
# (poste, depuis local/) nœud local
docker compose exec node1 tail -n 20 /var/log/fleetinfo/deploy.log

# (controller) VM GCP
ssh -i /root/.ssh/fleet_key ansible@<IP> sudo tail -n 20 /var/log/fleetinfo/deploy.log

# (controller) tous les serveurs du groupe web en une commande
ansible web -b -m ansible.builtin.command -a "tail -n 5 /var/log/fleetinfo/deploy.log"
ansible -i inventories/cloud/fleet.gcp.yml web -b -m ansible.builtin.command -a "tail -n 5 /var/log/fleetinfo/deploy.log"

# (serveur) uniquement les échecs
sudo grep -v 'resultat=SUCCES' /var/log/fleetinfo/deploy.log
```

### 1.2 Journaux nginx

Chemins fixés par [`roles/webserver/vars/main.yml`](../ansible/roles/webserver/vars/main.yml)
(`webserver_access_log`, `webserver_error_log`) et par le `nginx.conf` de `geerlingguy.nginx`.

| Fichier | Contenu |
|---|---|
| `/var/log/nginx/fleetinfo.access.log` | Requêtes vers le site Fleet Info (`/`, `/health`), format `combined` de nginx. Les contrôles de santé d'Ansible y apparaissent depuis `127.0.0.1` avec l'agent `ansible-httpget`. Les requêtes vers `/status` n'y figurent **pas** (`access_log off` sur cette location). |
| `/var/log/nginx/fleetinfo.error.log` | Erreurs du site, dont les **échecs d'authentification** sur `/status` (mauvais mot de passe, compte inconnu). Une requête **sans** identifiants reçoit 401 sans ligne d'erreur. |
| `/var/log/nginx/error.log` | Journal global (niveau `warn`, défini par le `nginx.conf` du rôle public) : erreurs de démarrage et de rechargement. |
| `/var/log/nginx/access.log` | Journal d'accès global, tamponné (`buffer=16k flush=2m`) ; normalement vide, toutes les requêtes étant servies par le site Fleet Info (`default_server`). |

Formes attendues des lignes (valeurs illustratives) :

```text
# fleetinfo.access.log : contrôle de santé lancé par Ansible depuis le serveur lui-même
127.0.0.1 - - [03/Nov/2026:19:17:26 +0100] "GET /health HTTP/1.1" 200 386 "-" "ansible-httpget"

# fleetinfo.error.log : mauvais mot de passe sur /status
... [error] ...: *23 user "exploitation": password mismatch, client: 172.20.0.1, server: _, request: "GET /status HTTP/1.1", host: "localhost:8081"
```

Un compte inconnu produit `user "<nom>" was not found in "/etc/nginx/fleetinfo-status.htpasswd"`.

```bash
# (serveur)
sudo tail -n 50 /var/log/nginx/fleetinfo.access.log
sudo tail -n 50 /var/log/nginx/fleetinfo.error.log
sudo tail -n 50 /var/log/nginx/error.log
```

### 1.3 journald (`journalctl`)

Les nœuds locaux (systemd en PID 1, ADR-03) et les VM utilisent systemd : les services y
journalisent de la même façon.

```bash
# (serveur)
sudo journalctl -u nginx -n 50 --no-pager      # démarrages, rechargements (Reloading/Reloaded), erreurs [emerg]
sudo journalctl -u ssh -n 50 --no-pager        # connexions SSH acceptées / refusées
sudo systemctl --failed                        # unités en échec
sudo journalctl -p err -b --no-pager           # toutes les erreurs depuis le démarrage
# (VM GCP uniquement) création de l'utilisateur ansible à partir de la métadonnée ssh-keys
sudo journalctl -u 'google-guest-agent*' --no-pager | grep -i ansible
```

Un rechargement de nginx par le handler « Recharger nginx » (ou par le `rescue` du
déploiement) apparaît sous la forme de deux lignes systemd `Reloading nginx.service` puis
`Reloaded nginx.service`. Un redémarrage (premier passage uniquement, ADR-10) apparaît en
`Stopping` / `Started`.

### 1.4 Sortie d'Ansible

| Option | Usage |
|---|---|
| (aucune) | `PLAY RECAP` : `ok`, `changed`, `unreachable`, `failed`, `skipped`, `rescued`, `ignored` par hôte. Un échec de déploiement rattrapé apparaît comme `failed=1 rescued=1` sur le canari (observé : `node1`). |
| `-v` | Résultat détaillé de chaque tâche (format YAML : `callback_result_format = yaml`). |
| `-vv` | Ajoute le chemin du fichier de chaque tâche. |
| `-vvv` | Ajoute les commandes de connexion SSH et le détail du chargement des inventaires (utile pour l'inventaire dynamique). |
| `-vvvv` | Ajoute le débogage du client SSH. |
| `--diff` | Différences ligne à ligne des fichiers générés (templates). |
| `--check --diff` | Simulation : ce qui **serait** modifié, sans rien modifier (sur des serveurs déjà déployés). |
| `--limit node1` | Restreint à un hôte. |
| `--tags fleetinfo` | Ne joue qu'une couche (`common`, `webserver` ou `fleetinfo`). |
| `--list-tasks`, `--list-tags`, `--list-hosts` | Affiche le plan sans l'exécuter. |

Message attendu en fin d'échec de déploiement rattrapé (reconstitué à partir de la tâche
« Faire échouer explicitement le déploiement », cas de la démonstration) :

```text
ÉCHEC du déploiement de Fleet Info 1.2.0 sur node1. Retour arrière effectué : la version 1.1.0 est de nouveau active et répond sur /health. Cause : Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found. Journal : /var/log/fleetinfo/deploy.log.
```

Conserver une trace d'une exécution (dans le controller, **hors** du dépôt monté, car la
sortie peut contenir des informations d'infrastructure) :

```bash
# (controller)
ANSIBLE_LOG_PATH=/tmp/ansible-run.log ansible-playbook site.yml -vv
```

La sortie de la tâche « Créer le compte d'accès à la page /status » est masquée
(`no_log: true`) : « the output has been hidden due to the fact that 'no_log: true' was
specified for this result ». Ne pas retirer `no_log` pour déboguer dans une sortie partagée.

### 1.5 Docker Compose (banc local)

```bash
# (poste)
cd local
docker compose ps                     # état et santé des conteneurs
docker compose logs controller        # message de l'entrypoint (clé SSH absente...)
docker compose logs node1             # console de systemd (PID 1)
docker inspect --format '{{json .State.Health}}' fleetinfo-local-node1-1   # détail du healthcheck sshd
```

Résultat attendu de `docker compose ps` : trois conteneurs `fleetinfo-local-controller-1`,
`fleetinfo-local-node1-1`, `fleetinfo-local-node2-1` à l'état `Up`, les deux nœuds
`(healthy)` avec les ports `0.0.0.0:8081->80/tcp` et `0.0.0.0:8082->80/tcp`.

`docker compose logs node1` ne montre que la console de systemd : les journaux de nginx et de
sshd d'un nœud sont dans son journald (section 1.3).

### 1.6 Terraform

```bash
# (poste) journal de débogage du provider, écrit hors du dépôt
TF_LOG=DEBUG terraform -chdir=terraform plan 2> /tmp/terraform-debug.log
```

Ce journal détaille les appels à l'API Google ; il peut contenir des informations sensibles
(jetons, IP) : ne jamais le versionner ni le partager tel quel.

### 1.7 Console série des VM (cloud)

Si une VM ne répond plus du tout en SSH, sa console série montre le démarrage et l'activité
de l'agent invité :

```bash
# (poste)
gcloud compute instances get-serial-port-output fleetinfo-web-1 --zone=<ZONE> | tail -n 50
```

---

## 2. Fichiers générés sur les serveurs

Les fichiers produits par **nos** templates commencent par l'en-tête défini dans
`ansible.cfg` (`ansible_managed`) :

```text
Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement
```

suivi d'une ligne `Source :` (ou d'une clé `_source` en JSON) qui indique le template d'origine.
L'en-tête est adapté au format : `#` (configuration, bannière), commentaire HTML (page), clé
`_ansible_managed` (JSON).

| Chemin sur le serveur | Produit par | Contenu, en-tête |
|---|---|---|
| `/etc/motd` | rôle `common`, `templates/motd.j2` | Bannière de connexion : hôte, environnement, système, compte d'exploitation, emplacements utiles (`common_motd_extra_lines`). En-tête `# Géré par Ansible…`. |
| `/etc/localtime` (fuseau) | rôle `common`, `community.general.timezone` | `Europe/Paris` (`common_timezone`). Vérifier : `timedatectl`. |
| `/home/fleetops/` | rôle `common`, `ansible.builtin.user` | Compte d'exploitation `fleetops`, groupes `adm` et `systemd-journal`, sans `sudo`. |
| `/etc/nginx/nginx.conf` | `geerlingguy.nginx`, template du rôle public | Configuration globale, validée par `nginx -t` avant écriture, inclut `/etc/nginx/conf.d/*.conf` et `/etc/nginx/sites-enabled/*`. En-tête `# Géré par Ansible…` ajouté par l'enveloppe `roles/webserver/templates/nginx.conf.j2` autour du template du rôle public (ADR-04). |
| `/etc/nginx/sites-enabled/default` | supprimé par `geerlingguy.nginx` | Absent (`nginx_remove_default_vhost: true`). `/etc/nginx/sites-available/default` reste présent mais n'est pas chargé. |
| `/etc/nginx/sites-enabled/fleetinfo.conf` | rôle `webserver`, `templates/fleetinfo.conf.j2` | Site Fleet Info : `/`, `/health`, `/status`. En-tête `# Géré par Ansible…`. |
| `/etc/nginx/fleetinfo-status.htpasswd` | rôle `webserver`, `community.general.htpasswd` | Compte `exploitation` et son empreinte `apr_md5_crypt` (`$apr1$…`). `root:www-data`, `0640`. Pas d'en-tête (fichier géré par le module, format imposé). |
| `/var/log/nginx/fleetinfo.access.log`, `fleetinfo.error.log` | nginx | Journaux du site (section 1.2). |
| `/opt/fleetinfo/releases/<version>/index.html` | rôle `fleetinfo`, `templates/index.html.j2` | Page d'accueil générée depuis les facts. En-tête en commentaire HTML `<!-- Géré par Ansible… -->` sur la première ligne. |
| `/opt/fleetinfo/releases/<version>/health.json` | rôle `fleetinfo`, `templates/health.json.j2` | Réponse de `/health` : clés `_ansible_managed`, `_source`, `status`, `application`, `version`, `environment`, `hostname`, `deployed_at`. Absent dans une release d'échec simulé. |
| `/opt/fleetinfo/current` | rôle `fleetinfo`, `ansible.builtin.file` | Lien symbolique vers la release active ; racine du site nginx (`webserver_document_root`). |
| `/etc/ansible/facts.d/fleetinfo.fact` | rôle `fleetinfo`, `templates/fleetinfo.fact.j2` | Fait local JSON : `version`, `previous_version`, `release_dir`, `deployed_at` (+ `_ansible_managed`, `_source`). Lu par Ansible sous `ansible_local.fleetinfo` (ADR-13). |
| `/var/log/fleetinfo/deploy.log` | rôle `fleetinfo`, `ansible.builtin.lineinfile` | Journal des tentatives (section 1.1). |
| `/home/ansible/.ssh/authorized_keys` | local : build de l'image (`local/node/Dockerfile`) ; cloud : agent invité GCE (métadonnée `ssh-keys` posée par Terraform) | Clé publique de déploiement (commentaire `fleetinfo-deploy`). |

Forme attendue de `health.json` (valeurs d'exemple ; clés dans l'ordre du template) :

```json
{
  "_ansible_managed": "Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement",
  "_source": "roles/fleetinfo/templates/health.json.j2",
  "status": "ok",
  "application": "fleetinfo",
  "version": "1.0.0",
  "environment": "local",
  "hostname": "node2",
  "deployed_at": "2026-11-03T18:00:00Z"
}
```

**Fichiers générés côté poste et controller** (jamais versionnés) :

| Chemin | Produit par | Contenu |
|---|---|---|
| `local/ssh/fleet_key`, `local/ssh/fleet_key.pub` | `local/scripts/generate-keys.sh` | Clé de déploiement ed25519. |
| `local/node/authorized_keys` | `local/scripts/generate-keys.sh` | Copie de la clé publique, intégrée à l'image des nœuds au build. |
| `/root/.ssh/fleet_key` (controller) | `local/controller/entrypoint.sh`, à chaque démarrage | Copie de la clé privée en `600`. |
| `/root/.ssh/known_hosts` (controller) | client SSH (`StrictHostKeyChecking=accept-new`) | Clés d'hôte des VM GCP ; perdu si le controller est recréé. |
| `ansible/collections/`, `ansible/roles/geerlingguy.nginx/` | `ansible-galaxy install -r requirements.yml` | Dépendances Galaxy aux versions épinglées. |
| `ansible/inventories/cloud/fleet.gcp.yml` | `scripts/prepare-cloud-inventory.sh` | Inventaire dynamique avec le `project_id` de la session. |
| `.secrets/gcp-adc.json` | `scripts/prepare-cloud-inventory.sh` | Copie des ADC `gcloud` (`600`), lue via `GOOGLE_APPLICATION_CREDENTIALS`. |
| `.vault_pass` | l'opérateur | Mot de passe du coffre Ansible Vault (`600`). |
| `terraform/terraform.tfstate`, `terraform/terraform.tfvars`, `terraform/.terraform/` | Terraform, l'opérateur | State local (ADR-05), valeurs de la session, providers téléchargés. |

---

## 3. Commandes de diagnostic

### 3.1 Banc local (poste)

```bash
cd local
docker compose ps                                    # node1 et node2 "(healthy)"
docker compose port node1 80                         # 0.0.0.0:8081
curl -s http://localhost:8081/health                 # JSON avec "status": "ok" et la version
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/status    # 401 (authentification requise)
docker compose exec node1 systemctl status nginx --no-pager              # active (running)
docker compose exec node1 nginx -t                   # syntax is ok / test is successful
docker compose exec node1 readlink -f /opt/fleetinfo/current             # /opt/fleetinfo/releases/<version>
docker compose exec node1 ls /opt/fleetinfo/releases                     # au plus 3 releases
docker compose exec node1 cat /etc/ansible/facts.d/fleetinfo.fact
docker system df                                     # espace disque consommé par Docker
```

### 3.2 Controller (Ansible, les deux environnements)

```bash
ansible --version | head -3            # ansible [core 2.17.14] ; config file = /workspace/ansible/ansible.cfg
ansible-galaxy collection list         # community.general 12.6.7, google.cloud 1.15.0 sous /workspace/ansible/collections
ansible-galaxy role list               # - geerlingguy.nginx, 3.3.1
ansible-config dump --only-changed     # réglages effectifs issus de ansible.cfg
ansible-inventory --graph              # local : @web -> node1, node2
ansible-inventory --host node1         # variables vues par Ansible pour un hôte
ansible web -m ansible.builtin.ping -o                           # node1 | SUCCESS ..., node2 | SUCCESS ...
ansible web -m ansible.builtin.setup -a 'filter=ansible_local'   # fait local fleetinfo (version, previous_version...)
ansible web -b -m ansible.builtin.command -a 'readlink -f /opt/fleetinfo/current'
ansible-playbook site.yml --check --diff                         # serveurs conformes : changed=0
ansible-playbook site.yml --limit node1 -vvv                     # exécution détaillée sur un hôte
ansible-lint                                                     # Passed: 0 failure(s), 0 warning(s)
ls -l /root/.ssh/fleet_key                                       # -rw------- (600)
ssh -i /root/.ssh/fleet_key ansible@node1                        # connexion manuelle à un nœud local
```

Équivalents cloud (résultats attendus, non encore observés) :

```bash
ls -l /workspace/.secrets/gcp-adc.json                                         # présent, -rw-------
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph                   # @web, @env_cloud, @zone_<zone> avec fleetinfo-web-1, -2
ansible-inventory -i inventories/cloud/fleet.gcp.yml --host fleetinfo-web-1    # ansible_host = IP publique, gce_zone, gce_machineType...
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph -vvv              # détail du chargement du plugin en cas d'inventaire vide
ansible -i inventories/cloud/fleet.gcp.yml web -m ansible.builtin.ping -o
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --check --diff
ssh -i /root/.ssh/fleet_key ansible@<IP>
```

### 3.3 Sur un serveur

```bash
sudo systemctl status nginx --no-pager
sudo nginx -t                                   # valide la configuration complète
sudo nginx -T | less                            # configuration effectivement chargée (tous les fichiers inclus)
sudo ss -ltnp | grep ':80 '                     # nginx écoute bien sur le port 80
readlink -f /opt/fleetinfo/current              # release active
ls -l /opt/fleetinfo/releases/
curl -s http://127.0.0.1/health                 # même contrôle que celui d'Ansible
cat /etc/ansible/facts.d/fleetinfo.fact
head -2 /etc/nginx/sites-enabled/fleetinfo.conf # en-tête "Géré par Ansible" + source
sudo tail -n 20 /var/log/fleetinfo/deploy.log
timedatectl | grep 'Time zone'                  # Europe/Paris
```

### 3.4 Terraform (poste)

```bash
terraform version                                        # Terraform >= 1.9 et < 2.0
terraform -chdir=terraform fmt -check -recursive         # aucune sortie = conforme
terraform -chdir=terraform validate                      # Success! The configuration is valid.
terraform -chdir=terraform plan                          # juste après apply : No changes.
terraform -chdir=terraform state list
terraform -chdir=terraform output                        # fleetinfo_urls, vm_public_ips, ssh_commands...
terraform -chdir=terraform output -raw project_id
```

Résultat attendu de `state list` (2 VM) :

```text
module.compute.google_compute_instance.this[0]
module.compute.google_compute_instance.this[1]
module.network.google_compute_firewall.allow_http
module.network.google_compute_firewall.allow_ssh
module.network.google_compute_network.this
module.network.google_compute_subnetwork.this
```

### 3.5 gcloud (poste)

```bash
gcloud config list                                       # account = compte du lab, project = <PROJECT_ID>
gcloud auth list                                         # compte actif marqué *
gcloud auth application-default print-access-token > /dev/null && echo "ADC OK"
gcloud services list --enabled --filter="name:compute.googleapis.com"
gcloud compute instances list --filter="labels.app=fleetinfo" \
  --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)"
gcloud compute firewall-rules list --filter="network~fleetinfo-vpc" \
  --format="table(name,sourceRanges.list(),targetTags.list())"
gcloud compute instances describe fleetinfo-web-1 --zone=<ZONE> --format="yaml(labels,tags,metadata)"
gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"   # OS Login au niveau projet ?
curl -4 -s https://ifconfig.me                              # IP publique actuelle, à comparer à ssh_source_ranges
```

Éviter `gcloud compute ssh` : cette commande crée sa propre clé
(`~/.ssh/google_compute_engine`) et l'ajoute aux métadonnées du projet. Utiliser la clé de
déploiement (`ssh -i /root/.ssh/fleet_key ansible@<IP>` depuis le controller).

---

## 4. Erreurs déjà rencontrées et leur solution

Statut de chaque entrée :

- **Rencontrée** : erreur réellement obtenue pendant le développement ou les tests du banc
  local.
- **Anticipée** : erreur prévisible (cloud non encore exécuté de bout en bout, ou cas non
  provoqué) ; le message indiqué est celui que produit le code du socle ou, à défaut, le
  message habituel de l'outil concerné, à confirmer.

Index :

| N° | Symptôme résumé | Statut |
|---|---|---|
| [1](#1-variable-du-coffre-indéfinie-plays-importés-depuis-playbooks) | Variable du coffre indéfinie (plays importés depuis `playbooks/`) | Rencontrée |
| [2](#2-simulation---check-en-échec-à-la-bascule-du-lien) | `--check` : « src file does not exist » à la bascule du lien | Rencontrée |
| [3](#3-ansible-lint--jinjaspacing) | `ansible-lint` : `jinja[spacing]` | Rencontrée |
| [4](#4-script-generate-keyssh-non-exécutable) | `generate-keys.sh` : « Permission non accordée » | Rencontrée |
| [5](#5-windows--ansiblecfg-ignoré-clé-ssh-refusée) | Windows : `ansible.cfg` ignoré, clé SSH refusée | Rencontrée |
| [6](#6-fichier-de-mot-de-passe-du-coffre-introuvable) | Fichier de mot de passe du coffre introuvable | Rencontrée |
| [7](#7-configuration-nginx-refusée-default-server-en-double-ipv6) | nginx : « duplicate default server », `listen [::]` | Rencontrée |
| [8](#8-cloud--ssh-inventaire-identifiants-os-login) | Cloud : clé d'hôte changée, inventaire vide, ADC, timeout SSH, OS Login | Anticipée |
| [9](#9-hôte-docker-presque-plein) | Hôte Docker presque plein | Rencontrée |
| [10](#10-page-régénérée-à-chaque-passage-fact-instable) | Page régénérée à chaque passage (fact instable) | Rencontrée |
| [11](#11-construction-des-nœuds-sans-clé-publique) | Construction des nœuds sans clé publique | Anticipée |
| [12](#12-terraform--validation-de-variable-refusée) | Terraform : validation de variable refusée | Rencontrée (tests de validation) |
| [13](#13-terraform--state-dune-session-précédente) | Terraform : state d'une session précédente | Anticipée |
| [14](#14-api-compute-engine-désactivée) | API Compute Engine désactivée | Anticipée |
| [15](#15-prepare-cloud-inventorysh-en-erreur) | `prepare-cloud-inventory.sh` en erreur (dont ADC sous Git Bash) | Anticipée |
| [16](#16-garde-fous-des-rôles-assertions) | Garde-fous des rôles (assertions) | Rencontrée (simulation sur version active) / anticipée |
| [17](#17-status-refuse-un-mot-de-passe-supposé-correct) | `/status` refuse un mot de passe supposé correct | Anticipée |
| [18](#18-mauvais-mot-de-passe-du-coffre) | Mauvais mot de passe du coffre | Anticipée |
| [19](#19-fichier-vault_pass-exécuté-comme-un-script-git-bash) | `.vault_pass` exécuté comme un script (Git Bash) | Anticipée |
| [20](#20-dépendances-galaxy-non-installées) | Dépendances Galaxy non installées | Anticipée |
| [21](#21-nœuds-locaux-en-échec-de-healthcheck) | Nœuds locaux en échec de healthcheck | Anticipée |
| [22](#22-configuration-du-site-refusée-avant-écriture) | Configuration du site refusée avant écriture (`validate`) | Rencontrée (test provoqué) |
| [23](#23-retour-arrière-non-confirmé-echec_rollback_ko) | Retour arrière non confirmé (`ECHEC_ROLLBACK_KO`) | Rencontrée (test provoqué) |

### 1. Variable du coffre indéfinie (plays importés depuis playbooks/)

- **Statut** : rencontrée.
- **Symptôme (message exact, fragment)** : le rôle `webserver` échoue sur une variable du coffre
  indéfinie :

  ```text
  'vault_webserver_status_password' is undefined
  ```

- **Cause** : Ansible charge les `group_vars` de playbook relativement au dossier **du playbook
  joué**. Des plays importés depuis `ansible/playbooks/` ne chargent pas
  `ansible/group_vars/all/` (`vars.yml` et le coffre `vault.yml`). Le réglage
  `playbook_vars_root` (`top`, `bottom`, `all`) a été testé sans résoudre le problème.
- **Solution** : les plays sont écrits directement dans `ansible/site.yml` (ADR-09). Tout nouveau
  playbook doit être placé dans `ansible/`, à côté de `site.yml` (comme `rollback.yml`).

### 2. Simulation --check en échec à la bascule du lien

- **Statut** : rencontrée.
- **Symptôme (message exact)** : `ansible-playbook site.yml --check --diff` avec une nouvelle
  version échoue sur la tâche « Basculer le lien current vers la release X.Y.Z » :

  ```text
  src file does not exist, use "force=yes" if you really want to create the link: /opt/fleetinfo/releases/1.1.0
  ```

- **Cause** : en simulation, le répertoire de la nouvelle release n'est pas réellement créé ; le
  module `file` refuse de créer un lien vers une cible absente.
- **Solution** : `force: "{{ ansible_check_mode }}"` sur la tâche de bascule (en place dans
  `roles/fleetinfo/tasks/deploy.yml`). Si l'erreur réapparaît, vérifier que ce paramètre n'a pas
  été retiré. Le contrôle de santé est, lui, sauté en `--check` (`when: not ansible_check_mode`).
  Résultat vérifié : `--check --diff` avec une nouvelle version annonce les changements sans
  erreur.

### 3. ansible-lint : jinja[spacing]

- **Statut** : rencontrée.
- **Symptôme (message exact)** :

  ```text
  jinja[spacing]: Jinja2 spacing could be improved
  ```

  signalé sur des blocs `{% if %}` placés dans des chaînes YAML repliées (`>-`).
- **Cause** : le profil `production` d'`ansible-lint` (fichier `ansible/.ansible-lint`) impose un
  formatage Jinja2 que les blocs de contrôle dans des chaînes repliées ne respectent pas.
- **Solution** : expressions déplacées dans des `vars:` de tâche, sous forme d'expressions
  conditionnelles (`'a' if condition else 'b'`), par exemple `fleetinfo_rollback_summary` et
  `fleetinfo_log_detail` dans `roles/fleetinfo/tasks/deploy.yml`. Vérification (controller) :
  `ansible-lint` → `Passed: 0 failure(s), 0 warning(s)`.

### 4. Script generate-keys.sh non exécutable

- **Statut** : rencontrée.
- **Symptôme (message exact)** :

  ```text
  bash: ./local/scripts/generate-keys.sh: Permission non accordée
  ```

  (sur un poste en anglais : `Permission denied`).
- **Cause** : le script était enregistré dans Git avec le mode `100644` (non exécutable).
- **Solution** : bit exécutable ajouté au script. Contournement immédiat, toujours valable :

  ```bash
  bash local/scripts/generate-keys.sh
  bash scripts/prepare-cloud-inventory.sh
  ```

  Vérifier le mode enregistré dans Git : `git ls-files -s local/scripts/generate-keys.sh`
  doit afficher `100755`. S'il affiche `100644` (correction pas encore committée, ou fichier
  ajouté depuis Windows, où Git ne voit pas le bit exécutable), enregistrer le mode puis
  committer :

  ```bash
  git update-index --chmod=+x local/scripts/generate-keys.sh scripts/prepare-cloud-inventory.sh
  ```

### 5. Windows : ansible.cfg ignoré, clé SSH refusée

**5a. `ansible.cfg` ignoré**

- **Statut** : rencontrée.
- **Symptôme (message exact)** :

  ```text
  [WARNING]: Ansible is being run in a world writable directory (/workspace/ansible), ignoring it as an ansible.cfg source.
  ```

  suivi d'effets en cascade : inventaire par défaut introuvable
  (`No inventory was parsed, only implicit localhost is available`), rôle
  `geerlingguy.nginx` introuvable, mot de passe du coffre non fourni.
- **Cause** : un dossier monté depuis Windows apparaît accessible en écriture à tous ; par
  sécurité, Ansible n'y lit pas `ansible.cfg` automatiquement.
- **Solution** : `ANSIBLE_CONFIG=/workspace/ansible/ansible.cfg` est positionnée par
  `local/docker-compose.yml` (et `.devcontainer/devcontainer.json`). Vérifier :
  `ansible --version | grep 'config file'` → `config file = /workspace/ansible/ansible.cfg`.
  Dans un autre shell ou conteneur, exporter cette variable.

**5b. Clé SSH refusée**

- **Statut** : rencontrée.
- **Symptôme (message exact)** :

  ```text
  WARNING: UNPROTECTED PRIVATE KEY FILE!
  Permissions 0777 for '/workspace/local/ssh/fleet_key' are too open.
  This private key will be ignored.
  ```

  puis `Permission denied (publickey)`.
- **Cause** : la clé montée depuis Windows apparaît en `777` et `chmod` n'a aucun effet sur ce
  montage ; `ssh` refuse une clé lisible par d'autres.
- **Solution** : l'entrypoint du controller copie la clé vers `/root/.ssh/fleet_key` en `600` à
  chaque démarrage, et les deux inventaires utilisent ce chemin (`ansible_ssh_private_key_file`).
  Si la clé a été générée **après** le démarrage du controller, ou si
  `docker compose logs controller` affiche
  `ATTENTION : /workspace/local/ssh/fleet_key introuvable.` :

  ```bash
  # (poste, depuis local/)
  docker compose restart controller
  docker compose exec controller ls -l /root/.ssh/fleet_key   # -rw------- 1 root root ...
  ```

### 6. Fichier de mot de passe du coffre introuvable

- **Statut** : rencontrée.
- **Symptôme (messages exacts)** : dès la première commande `ansible*` qui charge la
  configuration (par exemple `ansible-inventory --graph`). Dans le controller (observé le
  2026-11-04) :

  ```text
  Mot de passe Vault introuvable : créer socle-web-automatise/.vault_pass sur le poste (cf. README, Prérequis et accès).
  [WARNING]: Error in vault password file loading (default): Vault password
  script /usr/local/bin/fleet-vault-pass returned non-zero (1): None
  ERROR! Vault password script /usr/local/bin/fleet-vault-pass returned non-zero (1): None
  ```

  Hors controller (Ansible lancé directement sur un poste Linux, `ansible.cfg` seul) :
  `The vault password file .../socle-web-automatise/.vault_pass was not found`.
- **Cause** : le mot de passe du coffre est attendu dans `socle-web-automatise/.vault_pass` sur le
  poste (`/workspace/.vault_pass` dans le controller), fichier non versionné. Dans le
  controller, il est lu par le script `/usr/local/bin/fleet-vault-pass`
  (`ANSIBLE_VAULT_PASSWORD_FILE`) ; ailleurs, par `vault_password_file = ../.vault_pass`
  d'`ansible.cfg`.
- **Solution** (poste, depuis `socle-web-automatise/`) : récupérer le mot de passe auprès de
  l'équipe (section « Prérequis et accès » du [README](../README.md)), puis :

  ```bash
  printf '%s' 'MOT_DE_PASSE_VAULT_TRANSMIS_PAR_L_EQUIPE' > .vault_pass && chmod 600 .vault_pass
  ```

  Vérifier (controller) : `ansible-vault view group_vars/all/vault.yml` affiche le contenu
  déchiffré. Inutile de redémarrer le controller : le dépôt est monté.

### 7. Configuration nginx refusée (default server en double, IPv6)

**7a. Site `default` de Debian encore actif**

- **Statut** : rencontrée.
- **Symptôme (message exact, fragment)** : le handler « Valider la configuration nginx »
  (`nginx -t`) échoue avec :

  ```text
  duplicate default server
  ```

  (ligne complète de la forme `nginx: [emerg] a duplicate default server for 0.0.0.0:80 in /etc/nginx/sites-enabled/fleetinfo.conf:<ligne>`).
- **Cause** : le site `default` livré par Debian (`/etc/nginx/sites-enabled/default`) écoute lui
  aussi en `default_server` sur le port 80.
- **Solution** : `nginx_remove_default_vhost: true` dans les variables passées à
  `geerlingguy.nginx` (`roles/webserver/meta/main.yml`, en place). Si quelqu'un a recréé le site
  à la main : `ansible-playbook site.yml --tags webserver` le supprime. Vérifier (serveur) :
  `ls /etc/nginx/sites-enabled/` → `fleetinfo.conf` seul.

**7b. `listen [::]` sans IPv6**

- **Statut** : rencontrée.
- **Symptôme** : nginx refuse une directive `listen [::]:80` dans les conteneurs ; message
  habituel de nginx dans ce cas :

  ```text
  nginx: [emerg] socket() [::]:80 failed (97: Address family not supported by protocol)
  ```

- **Cause** : les conteneurs du banc local n'ont pas de pile IPv6. Les VM GCP du socle n'en ont
  pas non plus (sous-réseau IPv4 seul).
- **Solution** : le template `fleetinfo.conf.j2` n'écoute qu'en IPv4
  (`listen {{ webserver_listen_port }} default_server;`, commentaire explicatif dans le
  template) ; ne pas y ajouter de `listen [::]`.

### 8. Cloud : SSH, inventaire, identifiants, OS Login

Toutes ces entrées sont **anticipées** : le cloud n'a pas encore été exécuté de bout en bout.

**8a. Clé d'hôte changée**

- **Symptôme (message exact)** :

  ```text
  WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
  ```

  dans Ansible : `UNREACHABLE!` avec `Host key verification failed.`
- **Cause** : une IP publique éphémère déjà rencontrée est attribuée à une nouvelle VM (nouvelle
  session, VM recréée, ou arrêtée puis redémarrée) ; le `known_hosts` du controller contient
  l'ancienne clé et `StrictHostKeyChecking=accept-new` refuse une clé qui change.
- **Solution** (controller) :

  ```bash
  ssh-keygen -R <IP>
  # en début de nouvelle session de lab, toutes les VM sont nouvelles :
  rm -f /root/.ssh/known_hosts
  ```

**8b. Inventaire dynamique vide**

- **Symptôme** : `ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph` n'affiche que :

  ```text
  @all:
    |--@ungrouped:
  ```

  et `site.yml` affiche `skipping: no hosts matched`.
- **Causes possibles et vérifications** :

| Cause | Vérification | Solution |
|---|---|---|
| `project_id` d'une ancienne session dans `fleet.gcp.yml` | (controller) `grep -A1 '^projects' inventories/cloud/fleet.gcp.yml` | (poste) `./scripts/prepare-cloud-inventory.sh` |
| VM sans label `app=fleetinfo` (variable Terraform `app_name` modifiée) | (poste) `gcloud compute instances list --filter="labels.app=fleetinfo"` | Rétablir `app_name = "fleetinfo"` ou adapter le filtre du modèle `fleet.gcp.yml.example`. |
| VM pas encore `RUNNING` (création en cours) ou arrêtée | (poste) `gcloud compute instances list` (colonne `STATUS`) | Attendre ou démarrer la VM. |
| ADC d'un autre compte (sans accès au projet) | (poste) `gcloud auth list` ; (controller) `-vvv` sur `ansible-inventory` | (poste) `gcloud auth application-default login` avec le compte du lab, puis `./scripts/prepare-cloud-inventory.sh` |
| API Compute Engine désactivée | Avertissement `gcp_compute: skipping project '<PROJECT_ID>' (Compute Engine API is disabled).` (erreur n° 14) | `gcloud services enable compute.googleapis.com` |

  Les avertissements `Failed to parse ... fleet.gcp.yml ...` donnent la cause réelle ; ajouter
  `-vvv` pour plus de détails.

**8c. Identifiants GCP absents ou expirés (`DefaultCredentialsError`)**

- **Symptôme (message attendu)** : avertissements d'analyse de l'inventaire contenant :

  ```text
  File /workspace/.secrets/gcp-adc.json was not found.
  ```

  puis `No inventory was parsed, only implicit localhost is available`. Variantes :
  `Your default credentials were not found` (aucun fichier désigné), ou `invalid_grant` /
  `Reauthentication is needed` (ADC expirées ou révoquées).
- **Cause** : `.secrets/gcp-adc.json` n'a pas été créé, ou contient les ADC d'une session
  précédente.
- **Solution** (poste) :

  ```bash
  gcloud auth application-default login
  ./scripts/prepare-cloud-inventory.sh
  ```

  Inutile de redémarrer le controller : le fichier est lu à chaque exécution.

**8d. Timeout SSH**

- **Symptôme** : `UNREACHABLE!` avec
  `ssh: connect to host <IP> port 22: Connection timed out`.
- **Causes** :
  1. l'IP publique du poste a changé (autre réseau, VPN, partage de connexion) et n'est plus dans
     `ssh_source_ranges` ;
  2. la VM vient d'être créée et `sshd` n'est pas encore prêt.
- **Solution** (poste) :

  ```bash
  curl -4 -s https://ifconfig.me                  # IP publique actuelle
  # mettre à jour ssh_source_ranges = ["<IP>/32"] dans terraform/terraform.tfvars, puis :
  terraform -chdir=terraform apply             # mise à jour en place de fleetinfo-vpc-allow-ssh uniquement
  ```

  Le plan affiche la plage sous la forme `(sensitive value)`. Pour une VM tout juste créée,
  attendre une minute et relancer.

**8e. `Permission denied (publickey)` : utilisateur pas encore créé ou OS Login actif**

- **Symptôme** : `UNREACHABLE!` avec `Permission denied (publickey)` alors que la clé est la
  bonne.
- **Causes** :
  1. juste après `terraform apply`, l'agent invité GCE n'a pas encore créé l'utilisateur
     `ansible` : attendre une minute ;
  2. OS Login ignore la métadonnée `ssh-keys`. Les VM du socle posent
     `enable-oslogin = "FALSE"`, qui prime sur le réglage du projet, sauf si une politique
     d'organisation impose OS Login (`constraints/compute.requireOsLogin`).
- **Vérification** (poste) :

  ```bash
  gcloud compute instances describe fleetinfo-web-1 --zone=<ZONE> --format="yaml(metadata)"   # enable-oslogin: 'FALSE', ssh-keys: ansible:ssh-ed25519 ...
  gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"
  ```

  Sur la VM (console série, section 1.7) ou via `sudo journalctl -u 'google-guest-agent*'`, l'agent
  doit mentionner la création de l'utilisateur `ansible`.
- **Solution** : si OS Login est imposé par une politique, la méthode d'accès doit être revue
  (ADR-06, alternative OS Login). À relever lors de la première session ([lab-gcp.md](lab-gcp.md)).

### 9. Hôte Docker presque plein

- **Statut** : rencontrée.
- **Symptôme** : échec du build des images ou d'`apt` dans les nœuds, avec
  `no space left on device`.
- **Cause** : images et cache de build (environ 1 Go pour les images du banc) accumulés sur
  l'hôte Docker.
- **Solution** (poste) :

  ```bash
  docker system df              # espace utilisé et récupérable
  docker builder prune          # cache de build
  docker image prune            # images non référencées
  ```

  `docker system prune -a` supprime **toutes** les images inutilisées, y compris celles d'autres
  projets : à éviter sur un poste partagé.

### 10. Page régénérée à chaque passage (fact instable)

- **Statut** : rencontrée.
- **Symptôme** : le second `ansible-playbook site.yml` affiche `changed=1` sur la tâche
  « Générer la page d'accueil de la release » au lieu de `changed=0` (et une nouvelle ligne
  `type=mise-a-jour-sur-place` dans `deploy.log` à chaque passage).
- **Cause** : le template affiche une valeur qui change à chaque exécution (heure courante,
  uptime, charge, espace libre).
- **Solution** : ne jamais afficher ces valeurs (règle écrite en tête de
  `roles/fleetinfo/templates/index.html.j2`) ; la date du dernier déploiement vient du fait local
  (ADR-13). Pour identifier la ligne qui change (controller) :

  ```bash
  ansible-playbook site.yml --diff --limit node1
  ```

- **Cas normaux, à ne pas confondre** : un `changed` **unique** après la suppression de
  `/etc/ansible/facts.d/fleetinfo.fact`, ou au premier `site.yml` qui suit un `rollback.yml`
  (version alignée), est attendu : la page reprend la date mémorisée, puis redevient stable
  (ADR-13).

### 11. Construction des nœuds sans clé publique

- **Statut** : anticipée.
- **Symptôme** : `docker compose up -d --build --wait` échoue au build de l'image des nœuds,
  sur l'instruction `COPY authorized_keys`, avec un message indiquant que `authorized_keys`
  est introuvable (`not found`).
- **Cause** : `local/scripts/generate-keys.sh` n'a pas été lancé ; `local/node/authorized_keys`
  n'existe pas.
- **Solution** (poste, depuis `socle-web-automatise/`) :

  ```bash
  ./local/scripts/generate-keys.sh
  cd local && docker compose up -d --build --wait
  ```

### 12. Terraform : validation de variable refusée

- **Statut** : rencontrée lors des tests de validation (2026-11-03 et 2026-11-04 : `0.0.0.0/0`,
  `0.0.0.0/1` + `128.0.0.0/1`, `203.0.113.10/0` et une plage IPv6 en SSH, zone hors région,
  `vm_count = 0` puis `1`) ; les autres messages sont anticipés. Avec Terraform 1.17, `plan`
  affiche d'abord un plan partiel (ressources indépendantes de la variable invalide), puis
  l'erreur, et se termine en code retour 1 : rien n'est appliqué.
- **Symptôme (messages exacts, issus de `terraform/variables.tf`)**, précédés de
  `Error: Invalid value for variable` :

| Message | Cause | Solution |
|---|---|---|
| `ssh_source_ranges : plages IPv4 au format CIDR, préfixe /16 minimum (ex. ["203.0.113.10/32"]). Jamais 0.0.0.0/0. IP publique IPv4 du poste : curl -4 -s https://ifconfig.me` | `ssh_source_ranges` vide, mal formé (IP sans `/32`), en IPv6 (poste double pile : `curl` sans `-4` renvoie une IPv6), ou trop large (préfixe inférieur à `/16`, dont `0.0.0.0/0` et `0.0.0.0/1`). | Indiquer l'IPv4 publique du poste : `["<IP>/32"]`. |
| `La zone doit appartenir à la région choisie (ex. region = "us-central1" -> zone = "us-central1-f").` | `zone` hors de `region`. | Corriger `zone` ou `region`. |
| `vm_count doit être un entier entre 2 et 10 (le socle exige au moins 2 VM).` | `vm_count` hors bornes (ex. `1`, `0`, `11`). | `vm_count = 2` (ou plus). |
| `project_id doit être un identifiant de projet GCP valide (6 à 30 caractères : minuscules, chiffres, tirets).` | `project_id` vide, avec majuscules ou mal copié. | Copier l'identifiant depuis le panneau du lab ou `gcloud config get-value project`. |
| `Clé publique introuvable : lancer local/scripts/generate-keys.sh, ou corriger ssh_public_key_path.` | `local/ssh/fleet_key.pub` absent (y compris lors d'un `destroy`). | `./local/scripts/generate-keys.sh`, ou restaurer la clé utilisée lors de l'`apply`. |

### 13. Terraform : state d'une session précédente

- **Statut** : anticipée.
- **Symptôme** : au début d'une nouvelle session, `terraform plan` tente de relire des
  ressources de l'ancien projet : erreurs `googleapi: Error 403` sur
  `projects/<ancien projet>/...`, ou plan inattendu (ressources annoncées comme disparues).
- **Cause** : la session précédente s'est terminée sans `terraform destroy` (lab expiré) ; le
  state local (ADR-05) référence des ressources d'un projet supprimé.
- **Solution** (poste) : **uniquement** si l'ancien projet n'existe plus (lab terminé) :

  ```bash
  rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
  terraform -chdir=terraform plan      # attendu : Plan: 6 to add, 0 to change, 0 to destroy.
  ```

### 14. API Compute Engine désactivée

- **Statut** : anticipée.
- **Symptômes** :
  - `terraform plan` ou `apply` échoue avec un message du type
    `Error 403: Compute Engine API has not been used in project <numéro> before or it is disabled.`
    (raison `accessNotConfigured`) ;
  - l'inventaire dynamique est vide, avec l'avertissement (texte exact du plugin
    `google.cloud` 1.15.0) :

    ```text
    gcp_compute: skipping project '<PROJECT_ID>' (Compute Engine API is disabled).
    ```

- **Cause** : l'API `compute.googleapis.com` n'est pas (encore) activée dans le projet du lab.
- **Solution** (poste) :

  ```bash
  gcloud services enable compute.googleapis.com
  gcloud services list --enabled --filter="name:compute.googleapis.com"
  ```

  Si l'activation est refusée, le lab ne permet pas ce déploiement : le noter dans
  [lab-gcp.md](lab-gcp.md).

### 15. prepare-cloud-inventory.sh en erreur

- **Statut** : vérifiée pour le message « project_id introuvable » (2026-11-04) ; autres cas anticipés.
- **Symptômes (messages exacts du script)** :

| Message | Cause | Solution |
|---|---|---|
| `ERREUR : identifiants introuvables (<chemin>).` puis `Lancer d'abord : gcloud auth application-default login` | ADC absentes sur le poste. | `gcloud auth application-default login`, puis relancer le script. |
| `ERREUR : project_id invalide : '<valeur>'` | Valeur passée en argument mal formée (majuscules, espaces, identifiant tronqué). | Passer l'identifiant exact du projet, ou aucun argument. |
| `ERREUR : project_id introuvable dans les outputs Terraform.` puis `Lancer d'abord 'terraform -chdir=terraform apply', ou passer le projet en argument :` et `./scripts/prepare-cloud-inventory.sh <PROJECT_ID>` | Aucun output `project_id` lisible : `terraform apply` pas encore effectué, state absent, ou state antérieur à l'ajout de l'output. Les messages de Terraform sont masqués par le script. | `terraform -chdir=terraform apply`, puis relancer le script ; ou passer le projet en argument (ex. `qwiklabs-gcp-00-0123456789ab`). |

  Sous Windows avec Git Bash, `gcloud` range les ADC dans `%APPDATA%\gcloud\` : le script y
  cherche automatiquement s'il ne trouve pas `CLOUDSDK_CONFIG` (non rejoué sous Windows ;
  inutile sous WSL). En dernier recours, désigner le fichier explicitement :

  ```bash
  GOOGLE_APPLICATION_CREDENTIALS="$APPDATA/gcloud/application_default_credentials.json" ./scripts/prepare-cloud-inventory.sh
  ```

### 16. Garde-fous des rôles (assertions)

Messages produits volontairement par les rôles pour empêcher une opération dangereuse ou
invalide (texte exact, valeurs d'exemple).

| Message | Cause | Solution |
|---|---|---|
| `fleetinfo_simulate_failure=true exige une version DIFFÉRENTE de la version active (1.1.0), sinon il n'existerait aucune version vers laquelle revenir. Exemple : -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true` | Simulation d'échec demandée sur la version déjà active. | Choisir une version différente de l'active (lire `deploy.log` ou `/health`). |
| `Retour arrière manuel : ne pas passer -e fleetinfo_version (1.3.0) ; utiliser -e fleetinfo_rollback_version=X.Y.Z pour choisir la version cible.` | `rollback.yml` lancé avec `-e fleetinfo_version=...` (les extra vars détourneraient la bascule ; vérifié le 2026-11-04). | Relancer sans `-e fleetinfo_version`, avec `-e fleetinfo_rollback_version=X.Y.Z` si besoin. |
| `fleetinfo_version="1.2" n'est pas une version X.Y.Z valide (à corriger dans group_vars/all/vars.yml ou dans le -e de la commande).` | Format de version invalide. | Version au format `X.Y.Z`. |
| `Aucune version précédente valide n'est mémorisée sur node1 ("") : préciser la cible avec -e fleetinfo_rollback_version=X.Y.Z` | `rollback.yml` sans cible alors qu'aucune version précédente n'est connue (un seul déploiement). | `-e fleetinfo_rollback_version=X.Y.Z` avec une release présente. |
| `La release 1.0.0 est absente ou incomplète (pas de health.json) dans /opt/fleetinfo/releases. Releases présentes : 1.1.0, 1.2.0, 1.3.0.` | Release cible supprimée par le ménage (`fleetinfo_keep_releases`) ou release cassée (échec simulé). | Choisir une release listée, ou redéployer la version avec `ansible-playbook site.yml -e fleetinfo_version=X.Y.Z`. |
| `node1 n'est pas une Debian 12 sous systemd (Debian 13.1, systemd) : le socle ne supporte que cette cible.` | Cible non supportée (rôle `common`). | Utiliser une image Debian 12 (`debian-cloud/debian-12`, `debian:bookworm-slim`). |
| `Validation of arguments failed` suivi du nom de la variable | Type invalide détecté par `meta/argument_specs.yml` (par exemple une liste à la place d'une chaîne). | Corriger la valeur à l'endroit indiqué par [variables.md](variables.md). |

### 17. /status refuse un mot de passe supposé correct

- **Statut** : anticipée (le refus d'un mauvais mot de passe, lui, a été vérifié : 401).
- **Symptôme** : `curl -u exploitation:<mdp> http://localhost:8081/status` renvoie 401 ;
  `fleetinfo.error.log` contient `user "exploitation": password mismatch`.
- **Cause** : le mot de passe a été modifié dans le coffre sans relancer le rôle `webserver`,
  ou le mot de passe utilisé n'est pas celui du coffre actuel.
- **Solution** (controller) :

  ```bash
  ansible-vault view group_vars/all/vault.yml          # mot de passe actuel
  ansible-playbook site.yml --tags webserver           # réécrit le fichier htpasswd
  ```

  Procédure complète : [RB-05](runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).

### 18. Mauvais mot de passe du coffre

- **Statut** : anticipée.
- **Symptôme (message habituel d'Ansible)** :

  ```text
  ERROR! Decryption failed (no vault secrets were found that could decrypt) on /workspace/ansible/group_vars/all/vault.yml
  ```

- **Cause** : `.vault_pass` ne contient pas le bon mot de passe : ancien mot de passe après un
  `rekey`, faute de frappe, guillemets copiés avec le mot de passe, ou marque d'ordre des
  octets (BOM) ajoutée par un éditeur Windows. Les espaces et retours à la ligne en début ou en
  fin de fichier, eux, ne sont **pas** en cause : Ansible les retire à la lecture du fichier.
- **Solution** : récupérer le mot de passe actuel auprès de l'équipe et réécrire `.vault_pass`
  avec `printf '%s'` (erreur n° 6), plutôt qu'avec un éditeur de texte.

### 19. Fichier .vault_pass exécuté comme un script (Git Bash)

- **Statut** : anticipée ; **corrigée dans le controller** (non rejouée sous Windows).
- **Symptôme** : `Problem running vault password script /workspace/.vault_pass`.
- **Cause** : dépôt cloné sur un disque Windows (`C:\`) et monté dans le controller : le fichier
  apparaît exécutable (`777`), et Ansible **exécute** un fichier de mot de passe exécutable au
  lieu de le lire.
- **Correction en place** : le controller ne désigne plus `.vault_pass` directement.
  `ANSIBLE_VAULT_PASSWORD_FILE=/usr/local/bin/fleet-vault-pass` (`local/docker-compose.yml`)
  pointe vers un script de l'image (`local/controller/read-vault-password.sh`) qui **lit** la première
  ligne de `/workspace/.vault_pass` (CRLF retiré). L'erreur ne peut donc apparaître que si
  Ansible est lancé hors du controller avec un `.vault_pass` exécutable : dans ce cas,
  `chmod 600 .vault_pass` (WSL) ou passer par le controller.
- **Si le message apparaît malgré tout dans le controller** : vérifier que l'image est à jour
  (`docker compose up -d --build`) et que `env | grep ANSIBLE_VAULT` affiche bien
  `ANSIBLE_VAULT_PASSWORD_FILE=/usr/local/bin/fleet-vault-pass`.

### 20. Dépendances Galaxy non installées

- **Statut** : anticipée.
- **Symptôme (message habituel d'Ansible)** : `site.yml` échoue avant la première tâche avec
  `the role 'geerlingguy.nginx' was not found` ; l'inventaire cloud ne peut pas être lu
  (plugin `google.cloud.gcp_compute` introuvable) ; ou un module `community.general.*`
  inconnu.
- **Cause** : dossiers `ansible/roles/geerlingguy.nginx/` et `ansible/collections/` absents
  (ignorés par Git). L'entrypoint du controller les installe automatiquement au démarrage s'ils
  manquent ; sans accès Internet à ce moment-là, il affiche seulement
  `ATTENTION : installation Galaxy impossible ; relancer 'ansible-galaxy install -r requirements.yml'.`
  (visible avec `docker compose logs controller`).
- **Solution** (controller ; commande idempotente) :

  ```bash
  ansible-galaxy install -r requirements.yml
  ansible-galaxy role list               # - geerlingguy.nginx, 3.3.1
  ansible-galaxy collection list         # google.cloud 1.15.0, community.general 12.6.7
  ```

### 21. Nœuds locaux en échec de healthcheck

- **Statut** : anticipée.
- **Symptôme** : `docker compose up -d --build --wait` échoue avec un message du type
  `dependency failed to start: container fleetinfo-local-node1-1 is unhealthy` ; le controller
  ne démarre pas (il attend `service_healthy`).
- **Causes possibles** : systemd ne démarre pas dans le conteneur (conteneurs `privileged`
  refusés, hôte en cgroups v1, montage `/sys/fs/cgroup` impossible) ; `ssh` ne démarre pas.
- **Diagnostic** (poste, depuis `local/`) :

  ```bash
  docker compose logs node1                              # console de systemd
  docker info --format '{{.CgroupVersion}}'              # attendu : 2
  docker compose exec node1 systemctl status ssh --no-pager
  ```

- **Solution** : utiliser un Docker récent en cgroups v2 (Docker Desktop avec le moteur WSL 2
  sous Windows), autoriser les conteneurs privilégiés, puis
  `docker compose up -d --force-recreate --wait`.

### 22. Configuration du site refusée avant écriture

- **Statut** : rencontrée (test provoqué le 2026-11-04 avec `-e webserver_listen_port=99999`).
- **Symptôme** : la tâche `webserver : Déployer la configuration du site Fleet Info` échoue ; sa
  sortie contient l'erreur de nginx sur le fichier **candidat** (chemin temporaire), par exemple :

  ```text
  [emerg] 4654#4654: invalid port in "99999" of the "listen" directive in /home/ansible/.ansible/tmp/.../.source.conf:7
  ```

- **Cause** : l'option `validate:` de la tâche teste le site dans une configuration minimale
  (`nginx -t -q`) **avant** de l'écrire ; une valeur invalide (port, chemin, directive) est
  refusée. Le fichier en place `/etc/nginx/sites-enabled/fleetinfo.conf` n'est **pas** modifié,
  aucun handler n'est notifié, nginx continue de servir : le site reste en ligne.
- **Solution** : corriger la variable en cause (souvent dans `group_vars/all/vars.yml` ou un
  `-e`), puis `ansible-playbook site.yml --tags webserver`. Vérifier ensuite
  `ansible web -b -m ansible.builtin.command -a "nginx -t"` (controller).

### 23. Retour arrière non confirmé (ECHEC_ROLLBACK_KO)

- **Statut** : rencontrée (test provoqué le 2026-11-04 : `health.json` de la release N-1
  supprimé à la main, puis échec simulé).
- **Symptôme** : le déploiement échoue avec le message

  ```text
  ÉCHEC du déploiement de Fleet Info 1.3.0 sur node1. Retour arrière vers la version 1.0.0
  effectué mais NON confirmé : /health ne répond pas avec cette version. INTERVENTION MANUELLE
  requise (docs/troubleshooting.md). Cause : ...
  ```

  et le journal contient `resultat=ECHEC_ROLLBACK_KO detail="... / retour arrière non confirmé : ..."`.
- **Cause** : la nouvelle release a échoué au contrôle de santé, `current` a été rebasculé vers
  N-1, mais N-1 ne répond pas non plus correctement sur `/health` : nginx arrêté ou en erreur,
  release N-1 incomplète ou modifiée à la main, port de contrôle incorrect.
- **Diagnostic** (sur le serveur) :

  ```bash
  readlink /opt/fleetinfo/current                 # release servie
  ls -l "$(readlink /opt/fleetinfo/current)"      # index.html et health.json présents ?
  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/health
  sudo systemctl status nginx --no-pager ; sudo nginx -t
  sudo tail -5 /var/log/fleetinfo/deploy.log
  ```

- **Solution** : remettre une release saine en service en la **régénérant** avec `site.yml`
  (méthode recommandée, [RB-02](runbooks.md#rb-02-revenir-à-une-version-précédente)
  méthode (a)) : `ansible-playbook site.yml --limit <hôte> -e fleetinfo_version=<N-1>`, ou après
  correction de `group_vars/all/vars.yml`. Lors du test, `ansible-playbook site.yml` a régénéré la
  release 1.0.0 sur place et rétabli `/health`. Si nginx est en cause, corriger d'abord le
  service (`sudo nginx -t`, `sudo journalctl -u nginx -n 50 --no-pager`).

---

## 5. Arbre de décision : la page ne s'affiche pas

Commencer par identifier l'URL :

- local : `http://localhost:8081` (`node1`), `http://localhost:8082` (`node2`) ;
- cloud : `terraform -chdir=terraform output fleetinfo_urls` (poste).

```text
1. Que renvoie curl ?
   (poste)  curl -sS -o /dev/null -w '%{http_code}\n' <URL>/
   (poste)  curl -sS <URL>/health
   |
   +-- 200 et la page attendue ------------------> problème côté navigateur (cache, proxy) : rafraîchir, autre navigateur.
   |
   +-- 200 mais ancienne version ----------------> déploiement en échec et rollback (voulu) :
   |                                                lire deploy.log (section 1.1). resultat=ECHEC_ROLLBACK_OK = comportement normal.
   |                                                Avec le canari, les autres serveurs n'ont pas reçu la version.
   |                                                Ou fleetinfo_version non modifiée dans group_vars/all/vars.yml.
   |
   +-- page « Welcome to nginx! » ---------------> site default de Debian actif, fleetinfo.conf absent :
   |                                                (controller) ansible-playbook site.yml --tags webserver
   |
   +-- 404 sur / ou sur /health -----------------> release absente ou incomplète :
   |                                                (serveur) readlink -f /opt/fleetinfo/current ; ls /opt/fleetinfo/releases/<v>/
   |                                                lien absent       -> le déploiement n'a jamais été joué : ansible-playbook site.yml
   |                                                health.json absent -> release cassée (ECHEC_SANS_ROLLBACK ?) :
   |                                                   redéployer une version saine, ou
   |                                                   ansible-playbook rollback.yml -e fleetinfo_rollback_version=X.Y.Z
   |
   +-- 401 sur / ou /health ---------------------> anormal (seul /status est protégé) : vérifier fleetinfo.conf (nginx -T)
   |
   +-- 500 / 502 / 403 --------------------------> (serveur) sudo tail /var/log/nginx/fleetinfo.error.log
   |                                                (droits sur /opt/fleetinfo, lien current cassé)
   |
   +-- Connection refused -----------------------> rien n'écoute sur le port : aller en 2.
   |   (en local, le proxy de ports de Docker accepte la connexion puis la ferme : le même cas
   |    apparaît en « Connection reset by peer » ou « Empty reply from server »)
   |
   +-- Timeout ----------------------------------> réseau : aller en 3.

2. Connection refused
   LOCAL : (poste, local/) docker compose ps
           |-- nœud absent ou non "(healthy)"  -> docker compose up -d --wait ; docker compose logs node1 ;
           |                                      disque plein (erreur n° 9) ; healthcheck (erreur n° 21)
           |-- nœud sain                       -> docker compose port node1 80 (attendu 0.0.0.0:8081)
   LES DEUX : (serveur) sudo systemctl status nginx --no-pager
           |-- nginx absent                    -> site.yml jamais joué sur ce serveur : (controller) ansible-playbook site.yml
           |-- nginx failed                    -> sudo nginx -t ; sudo journalctl -u nginx -n 50 --no-pager
           |                                      configuration modifiée à la main sur le serveur ? site.yml la rétablit :
           |                                      ansible-playbook site.yml --tags webserver
           |-- nginx actif                     -> sudo ss -ltnp | grep ':80 ' ; vérifier socle_http_port / webserver_listen_port

3. Timeout (cloud)
   (poste) gcloud compute instances list --filter="labels.app=fleetinfo"
           |-- VM absente                      -> terraform -chdir=terraform plan, puis apply
           |-- VM pas RUNNING                  -> attendre ou démarrer la VM (l'IP éphémère peut changer :
           |                                      terraform -chdir=terraform apply -refresh-only, puis output fleetinfo_urls)
           |-- VM RUNNING                      -> (poste) gcloud compute firewall-rules list --filter="network~fleetinfo-vpc" \
                                                    --format="table(name,sourceRanges.list(),targetTags.list())"
                                                  fleetinfo-vpc-allow-http doit autoriser la source du client sur le port 80
                                                  et cibler le tag fleetinfo-web porté par la VM.
                                                  Puis tester depuis la VM : curl -s http://127.0.0.1/health
                                                  OK sur la VM mais pas depuis le poste -> firewall ou IP publique erronée.
```

Si la page s'affiche mais qu'Ansible ne parvient pas à se connecter (SSH), voir les erreurs
n° 5b, 8a, 8d et 8e.
