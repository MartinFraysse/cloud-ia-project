# Script de démonstration : soutenance et passation

Ce document est le script de la démonstration de la soutenance. Il suit **exactement** les dix
étapes du scénario imposé (§8 des consignes), sur une session de lab GCP neuve dont
l'environnement a été préparé à l'avance. Pour chaque étape : où taper, la commande exacte, le
résultat attendu et ce qu'il faut dire ou montrer.

Si le cloud n'est pas disponible, la démonstration se fait intégralement en local :
voir [Plan B](#plan-b--démonstration-intégrale-en-local).

Documents liés : [runbooks](runbooks.md) (l'examinateur peut demander d'en dérouler un en
direct), [décisions techniques](decisions.md), [dépannage](troubleshooting.md),
[contraintes du lab GCP](lab-gcp.md), [README principal](../README.md).

> **Statut de validation.** Les étapes cloud n'ont pas encore été exécutées sur un projet GCP réel
> (session de lab expirée pendant le développement) : leurs sorties sont des **résultats
> attendus**, à confirmer lors de la répétition générale. Les sorties du
> [Plan B](#plan-b--démonstration-intégrale-en-local) ont été observées sur le banc local le
> 2026-11-03.

## Organisation

Trois fenêtres suffisent :

| Repère | Fenêtre | Emplacement |
|---|---|---|
| **A** | Terminal du poste (bash : Linux, macOS, WSL ou Git Bash) | `Project-1/socle-web-automatise/` |
| **B** | Shell du controller (`cd local && docker compose exec controller bash`) | `/workspace/ansible` |
| **N** | Navigateur | pages Fleet Info |

Répartition et minutage (durées **cibles**, à chronométrer lors de la répétition générale ; tous
les membres de l'équipe doivent participer, colonne « Qui » à remplir) :

| Étape | Sujet | Durée cible | Qui |
|---|---|---|---|
| 1 | `terraform apply` puis `terraform plan` | 2 min | |
| 2 | `ansible-inventory --graph` | 1 min | |
| 3 | Premier `site.yml` | 2 min 30 | |
| 4 | Second `site.yml` : `changed=0` | 1 min | |
| 5 | SSH sur une VM, en-tête d'un fichier généré | 1 min 30 | |
| 6 | Nouvelle version | 1 min 30 | |
| 7 | Échec volontaire, rollback, journal | 2 min | |
| 8 | `/status` refusé puis accepté | 1 min | |
| 9 | Environnement local | 1 min 30 | |
| 10 | `terraform destroy` | 1 min | |
| | **Total** | **15 min** | |

Dans ce document, `<PROJECT_ID>` désigne l'identifiant du projet du lab (de la forme
`qwiklabs-gcp-00-0123456789ab`) ; `203.0.113.10` et `203.0.113.11` représentent les IP publiques
de `fleetinfo-web-1` et `fleetinfo-web-2` : remplacez-les par les valeurs réelles affichées par
`terraform -chdir=terraform output vm_public_ips`.

---

## Préparation

### La veille

- [ ] Dépôt à jour et propre : `git pull`, puis `git status` sans modification ;
      `grep -n '^fleetinfo_version' ansible/group_vars/all/vars.yml` affiche
      `13:fleetinfo_version: "1.0.0"`.
- [ ] Outils présents sur le poste : `docker compose version`, `terraform version` (`~> 1.9`),
      `gcloud version`.
- [ ] Clé SSH de déploiement : `./local/scripts/generate-keys.sh` affiche
      `Clé déjà présente : ... (conservée).` (ou crée la clé).
- [ ] Mot de passe Vault : fichier `.vault_pass` présent à la racine du socle (transmis par
      l'équipe, hors Git) ; `ls -l .vault_pass` affiche `-rw-------`.
- [ ] Images Docker **déjà construites** et banc démarré (le premier build télécharge environ 1 Go) :

  ```bash
  # (A)
  cd local && docker compose up -d --build --wait && cd ..
  ```

- [ ] Dans le controller (B) : `ansible-galaxy install -r requirements.yml` (résultat attendu :
      `geerlingguy.nginx (3.3.1) is already installed, skipping.` et
      `Nothing to do. All requested collections are already installed.`).
- [ ] Coffre lisible (B) : `ansible-vault view group_vars/all/vault.yml > /dev/null && echo OK`
      affiche `OK`.
- [ ] Qualité : `ansible-lint` dans le controller (`Passed: 0 failure(s), 0 warning(s)`) ; sur le
      poste, `terraform -chdir=terraform init`, `terraform -chdir=terraform fmt -check -recursive`
      (aucune sortie) et `terraform -chdir=terraform validate` (`Success! The configuration is valid.`).
- [ ] Répétition complète et chronométrée du [Plan B](#plan-b--démonstration-intégrale-en-local),
      et, si une session de lab est disponible, répétition générale du scénario cloud complet
      (y relever la durée du lab et les sorties réelles).
- [ ] Remise à zéro du banc local après la répétition (nœuds neufs, puis version de référence) :

  ```bash
  # (A) depuis local/
  docker compose up -d --force-recreate --wait node1 node2
  # (B)
  ansible-playbook site.yml
  ```

- [ ] Espace disque Docker suffisant : `docker system df`.
- [ ] Étapes réparties entre les membres ; chacun sait dérouler chaque [runbook](runbooks.md).

### 30 minutes avant (session de lab neuve)

- [ ] Démarrer le lab ; relever la **durée affichée** dans le panneau (à reporter dans
      [lab-gcp.md](lab-gcp.md)), le `<PROJECT_ID>`, la région et la zone autorisées (session
      précédente : `us-central1` / `us-central1-f`). Ouvrir la console en navigation privée avec
      le compte du lab (`student-XX-...@qwiklabs.net`).
- [ ] Identifiants gcloud, avec le compte **du lab** dans les deux fenêtres d'authentification :

  ```bash
  # (A)
  gcloud auth login
  gcloud config set project <PROJECT_ID>
  gcloud auth application-default login
  gcloud compute zones list --filter="name~^us-central1"
  ```

  Résultat attendu : `Updated property [core/project].`, puis
  `Credentials saved to file: [...application_default_credentials.json]` ; la dernière commande
  liste les zones de la région (API Compute Engine accessible).
- [ ] Aucun state d'une session précédente : `terraform -chdir=terraform state list` n'affiche
      aucune ressource (aucune ligne si la session précédente s'est terminée par un `destroy`,
      ou `No state file was found!` si aucun `apply` n'a jamais été fait sur ce poste ; les deux
      cas conviennent). S'il liste des ressources, et seulement si l'ancien projet n'existe plus :
      `rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup`
      ([dépannage](troubleshooting.md), erreur n° 13).
- [ ] IP publique **du jour** (le réseau de la salle diffère de celui de la répétition) :
      `curl -4 -s https://ifconfig.me ; echo`.
- [ ] `terraform/terraform.tfvars` (s'il n'existe pas encore :
      `cp terraform/terraform.tfvars.example terraform/terraform.tfvars`) : `project_id`,
      `region`, `zone`, `vm_count = 2`, `ssh_source_ranges = ["<IP du jour>/32"]`. Le fichier
      d'une répétition précédente est conservé (ignoré par Git) : remplacer son `project_id` et
      son IP.
- [ ] `terraform -chdir=terraform plan` : `Plan: 6 to add, 0 to change, 0 to destroy.` Ne pas
      appliquer (sauf variante B de l'étape 1).
- [ ] Inventaire dynamique et identifiants du controller, préparés **avant** l'apply en passant le
      projet en argument (sans argument, le script lit `terraform output`, vide tant que l'apply
      n'a pas eu lieu) :

  ```bash
  # (A)
  ./scripts/prepare-cloud-inventory.sh <PROJECT_ID>
  ```

  Résultat attendu : `Inventaire généré : ansible/inventories/cloud/fleet.gcp.yml (projet <PROJECT_ID>)`
  puis `Identifiants copiés : .secrets/gcp-adc.json (lus par le controller)`.
- [ ] Banc démarré (`cd local && docker compose up -d --wait`) et terminal B ouvert. Dans B :

  ```bash
  # (B) oublier les clés d'hôte des VM de la répétition (IP éphémères réattribuables)
  rm -f /root/.ssh/known_hosts
  # identifiants et accès à l'API : aucune VM avant l'apply
  ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
  # banc local prêt pour l'étape 9
  ansible-playbook site.yml
  ```

  Résultat attendu : `--graph` s'exécute sans avertissement et n'affiche que `@all` et
  `@ungrouped` ; `site.yml` donne `changed=0` sur `node1` et `node2`.
- [ ] Terminaux A et B ouverts, police agrandie ; navigateur avec `http://localhost:8081` et
      `http://localhost:8082`.
- [ ] Variante B de l'étape 1 retenue : lancer `terraform -chdir=terraform apply` au début de la
      présentation.

### 5 minutes avant

- [ ] `git status` : aucune modification ; `vars.yml` en `1.0.0`.
- [ ] IP publique inchangée (`curl -4 -s https://ifconfig.me`).
- [ ] Temps restant dans le lab suffisant pour tout le scénario, `terraform destroy` compris.

---

## Déroulé

### Étape 1 : `terraform apply` puis `terraform plan`

**Où :** terminal A.

Variante A (recommandée si le minutage de la répétition le permet) : création en direct.

```bash
# (A)
terraform -chdir=terraform apply
# relire le plan, puis répondre : yes
terraform -chdir=terraform plan
```

Variante B (plus sûre si le temps est compté) : `terraform -chdir=terraform apply` lancé au début
de la présentation ; à l'étape 1, relancer les deux mêmes commandes.

**Résultat attendu :**

- plan de l'apply : `Plan: 6 to add, 0 to change, 0 to destroy.` avec
  `module.network.google_compute_network.this`, `module.network.google_compute_subnetwork.this`,
  `module.network.google_compute_firewall.allow_http`, `module.network.google_compute_firewall.allow_ssh`,
  `module.compute.google_compute_instance.this[0]` et `[1]` ; le `source_ranges` de la règle SSH
  apparaît `(sensitive value)` ;
- `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.` (variante B :
  `No changes.` puis `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`), suivi des
  outputs (`fleetinfo_urls`, `vm_public_ips`, `network_name = "fleetinfo-vpc"`,
  `subnet_name = "fleetinfo-subnet-us-central1"`...) ;
- `terraform plan` : `No changes. Your infrastructure matches the configuration.`

**À dire / à montrer :**

- Terraform crée l'infrastructure, et rien d'autre : VPC dédié `fleetinfo-vpc` (pas le réseau
  `default`), sous-réseau `10.10.0.0/24`, deux règles de firewall ciblant le tag réseau
  `fleetinfo-web`, deux VM Debian 12 `fleetinfo-web-1` et `-2`. Aucun paquet n'est installé par
  Terraform (pas de startup-script) : c'est le travail d'Ansible.
- Deux modules locaux (`modules/network`, `modules/compute`), reliés dans `main.tf` : le module VM
  reçoit l'identifiant du sous-réseau en sortie du module réseau (ADR-12).
- HTTP ouvert ; SSH ouvert **uniquement** à l'IP publique de l'opérateur en `/32`, variable
  sensible, `0.0.0.0/0` refusé par une validation (ADR-06).
- Labels `app`, `env`, `role`, `team` sur chaque VM : ce sont eux qu'utilise l'inventaire
  dynamique. Le nombre de VM ne dépend que de `vm_count`.
- Versions épinglées (`required_version = "~> 1.9"`, provider `google` `~> 8.9`, fichier de lock
  versionné) ; state local justifié par le lab éphémère (ADR-05).
- Le second `plan` prouve l'idempotence Terraform.

### Étape 2 : `ansible-inventory --graph`

**Où :** terminal B.

```bash
# (B)
ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
ansible -i inventories/cloud/fleet.gcp.yml web -m ansible.builtin.ping
```

**Résultat attendu :**

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

L'ordre des groupes peut différer. Le `ping` renvoie `"ping": "pong"` pour chaque VM (la première
connexion enregistre la clé d'hôte, `StrictHostKeyChecking=accept-new`). En cas de
`Permission denied (publickey)` juste après l'apply, l'agent invité GCE n'a pas encore créé
l'utilisateur `ansible` : attendre une minute et relancer le `ping`
([dépannage](troubleshooting.md), erreur n° 8).

**À dire / à montrer :**

- Plugin `google.cloud.gcp_compute` (collection `google.cloud` 1.15.0, version épinglée dans
  `requirements.yml`).
- Montrer `inventories/cloud/fleet.gcp.yml.example` : filtre `labels.app = fleetinfo` et
  `status = RUNNING`, `compose` qui calcule `ansible_host` depuis l'IP publique (`natIP`),
  `keyed_groups` qui transforme le label `role=web` en groupe `web`, **le même nom** qu'en local
  (ADR-07). Aucune IP n'est écrite dans le dépôt.
- Le `project_id` n'est jamais versionné : `fleet.gcp.yml` est généré (fichier ignoré par Git) par
  `scripts/prepare-cloud-inventory.sh`, car l'option `projects` du plugin n'a pas de variable
  d'environnement.
- Facultatif :
  `ansible-inventory -i inventories/cloud/fleet.gcp.yml --host fleetinfo-web-1 | grep -E '"(ansible_host|gce_zone|gce_machineType)"'`
  montre l'IP publique, la zone et le type de machine lus dans l'API.

### Étape 3 : `ansible-playbook site.yml`

**Où :** terminal B, puis A et le navigateur.

```bash
# (B)
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
# (A)
terraform -chdir=terraform output fleetinfo_urls
```

**Résultat attendu :**

- trois plays : `Appliquer le socle système commun`, `Configurer le serveur web nginx`,
  `Déployer l'application Fleet Info` ; dans le troisième, le premier hôte du groupe `web` (en
  principe `fleetinfo-web-1`) est traité seul (canari), puis les autres ;
- à la fin du deuxième play, les handlers du rôle public (`restart nginx` au premier passage,
  `reload nginx`) puis les nôtres, `Valider la configuration nginx` et `Recharger nginx` ;
- PLAY RECAP : `changed` > 0, `unreachable=0`, `failed=0` pour les deux VM ;
- `fleetinfo_urls` affiche une URL par VM ; chacune ouvre une page Fleet Info : environnement
  `cloud`, version `1.0.0`, rubrique « Cloud · Google Compute Engine » (zone `us-central1-f`, type
  de machine `e2-small`), bandeau bleu.

**À dire / à montrer (pendant l'exécution) :**

- Un seul point d'entrée, trois plays courts, la logique est dans les rôles `common`, `webserver`
  (appuyé sur le rôle public `geerlingguy.nginx` 3.3.1, ADR-04) et `fleetinfo` (écrit par
  l'équipe). Modules en FQCN, tags `common`, `webserver`, `fleetinfo`.
- Comparer les deux pages : nom d'hôte, FQDN, IP interne et IP publique différents ; même
  template `index.html.j2`, alimenté par les facts de chaque machine.
- La rubrique Cloud vient des `group_vars` de l'inventaire cloud (`gce_zone`, `gce_machineType`) ;
  en local elle est absente, sans champ vide (étape 9).
- Afficher `http://203.0.113.10/health` : JSON avec `status`, `version`, `environment`,
  `hostname`, `deployed_at`.
- Le seul redémarrage de nginx est celui du rôle public au premier passage (suppression du site
  `default` de Debian) ; ensuite, uniquement des rechargements (ADR-10).

### Étape 4 : second `ansible-playbook site.yml` : `changed=0`

**Où :** terminal B.

```bash
# (B)
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
```

**Résultat attendu :** PLAY RECAP `changed=0`, `unreachable=0`, `failed=0` pour
`fleetinfo-web-1` et `fleetinfo-web-2` (en local, sur la même base de code :
`ok=39 changed=0 failed=0` sur chaque nœud, observé le 2026-11-03).

**À dire / à montrer :**

- Idempotence : aucun fichier réécrit, aucun handler, aucune ligne ajoutée au journal de
  déploiement.
- La date du dernier déploiement affichée sur la page est mémorisée dans un fait local
  (`/etc/ansible/facts.d/fleetinfo.fact`) ; la page n'affiche aucune valeur instable (heure
  courante, uptime, espace libre), sinon `changed=0` serait impossible (ADR-13). L'en-tête
  `ansible_managed` ne contient ni date ni chemin absolu, pour la même raison.

### Étape 5 : connexion SSH et en-tête d'un fichier généré

**Où :** terminal A (ou B, voir ci-dessous).

```bash
# (A) IP de fleetinfo-web-1 : terraform -chdir=terraform output vm_public_ips
ssh -i local/ssh/fleet_key -o StrictHostKeyChecking=accept-new ansible@203.0.113.10
# (serveur)
head -n 2 /etc/nginx/sites-enabled/fleetinfo.conf
head -n 2 /opt/fleetinfo/current/index.html
cat /opt/fleetinfo/current/health.json
ls -l /opt/fleetinfo /opt/fleetinfo/releases
exit
```

Sous Windows, si `ssh` refuse la clé à cause de ses droits, se connecter depuis le controller :
`ssh -i /root/.ssh/fleet_key ansible@203.0.113.10` (terminal B).

**Résultat attendu :**

- à la connexion, la bannière `/etc/motd` : `Socle Web Automatisé - NovaRetail`, `Hôte`,
  `Environnement : cloud`, emplacements de la release active, du journal et du site nginx ;
- en tête de `fleetinfo.conf` :

  ```text
  # Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement
  # Source : roles/webserver/templates/fleetinfo.conf.j2
  ```

- `index.html` : même texte en commentaire HTML, puis
  `<!-- Source : roles/fleetinfo/templates/index.html.j2 (rôle fleetinfo, release 1.0.0) -->` ;
- `health.json` : clés `_ansible_managed` et `_source` en tête ;
- `current -> /opt/fleetinfo/releases/1.0.0`.

**À dire / à montrer :**

- Laisser l'examinateur choisir le fichier parmi : `/etc/nginx/sites-enabled/fleetinfo.conf`,
  `/opt/fleetinfo/current/index.html`, `/opt/fleetinfo/current/health.json`, `/etc/motd`,
  `/etc/ansible/facts.d/fleetinfo.fact`, et même `/etc/nginx/nginx.conf` (template du rôle public
  enveloppé par `roles/webserver/templates/nginx.conf.j2`, qui ajoute l'en-tête).
- L'en-tête vient de `ansible_managed` (`ansible.cfg`) ; la ligne `Source` indique le template
  d'origine, rangé dans `templates/` sous le nom `<fichier cible>.j2`.
- Accès SSH : clé ed25519 générée localement, jamais committée, injectée par la métadonnée
  `ssh-keys` ; OS Login désactivé sur les VM (ADR-06).

### Étape 6 : déploiement d'une nouvelle version

**Où :** terminal A, puis B, puis le navigateur.

```bash
# (A) modifier LA variable de version (ou l'éditer dans VS Code) ; sous macOS : sed -i ''
sed -i 's/^fleetinfo_version: .*/fleetinfo_version: "1.1.0"/' ansible/group_vars/all/vars.yml
git diff ansible/group_vars/all/vars.yml
# (B)
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo
# (A)
curl -s http://203.0.113.10/health
curl -s http://203.0.113.11/health
```

**Résultat attendu :**

- `git diff` : une seule ligne, `-fleetinfo_version: "1.0.0"` / `+fleetinfo_version: "1.1.0"` ;
- `fleetinfo-web-1` traité seul, puis `fleetinfo-web-2` ; tâches
  `Basculer le lien current vers la release 1.1.0` et
  `Interroger /health jusqu'à obtenir la version 1.1.0` réussies ; PLAY RECAP `failed=0` ;
- `/health` : `"version": "1.1.0"` sur les deux VM ;
- pages rechargées : badge `Fleet Info v1.1.0`, `Version précédente 1.0.0`, nouvelle date de
  déploiement, note « Mise à jour applicative (démonstration du déploiement d'une nouvelle version). ».

**À dire / à montrer :**

- Une seule variable, à un seul endroit (`group_vars/all/vars.yml`), commune aux deux
  environnements ([RB-01](runbooks.md#rb-01-déployer-une-nouvelle-version)).
- Chaque release a son répertoire (`/opt/fleetinfo/releases/1.1.0`) ; le lien `current` bascule
  de façon atomique, sans rechargement de nginx ; `/health` est contrôlé par
  `ansible.builtin.uri` (statut **et** version) ; déploiement canari ; trois releases conservées
  (ADR-08).

### Étape 7 : déploiement volontairement en échec, rollback et journal

**Où :** terminal B, puis A.

```bash
# (B) version DIFFÉRENTE de la version active (1.1.0), sinon un garde-fou refuse la simulation
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true
# (A) le site est resté en ligne en N-1
curl -s http://203.0.113.10/health
curl -s http://203.0.113.11/health
# (B) l'échec est tracé dans le journal du canari, et seulement du canari
ansible -i inventories/cloud/fleet.gcp.yml web -b -m ansible.builtin.command -a "tail -n 2 /var/log/fleetinfo/deploy.log"
```

**Résultat attendu :**

- sur le canari (`fleetinfo-web-1`) uniquement : bascule vers `1.2.0`, lignes `FAILED - RETRYING`
  sur `Interroger /health jusqu'à obtenir la version 1.2.0`, puis `Status code was 404` ;
  `rescue` : `Rebasculer current vers la release précédente 1.1.0`, `Recharger le service web`,
  `Vérifier que /health répond de nouveau avec la version 1.1.0`, puis échec explicite :
  `ÉCHEC du déploiement de Fleet Info 1.2.0 sur fleetinfo-web-1. Retour arrière effectué : la version 1.1.0 est de nouveau active et répond sur /health. ...` ;
- `fleetinfo-web-2` ne reçoit jamais la version `1.2.0` ; PLAY RECAP : `failed=1 rescued=1` pour
  `fleetinfo-web-1`, `failed=0` pour `fleetinfo-web-2` ; la commande rend un code retour non nul ;
- `/health` : `"version": "1.1.0"` sur les deux VM ;
- journal de `fleetinfo-web-1` (dernière ligne) :

  ```text
  <date> hote=fleetinfo-web-1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
  ```

  journal de `fleetinfo-web-2` : ses deux lignes `resultat=SUCCES` (`1.0.0` puis `1.1.0`), aucune
  ligne `1.2.0`.

Ensuite, prouver qu'une version saine passe normalement (recommandé, environ 1 minute) :

```bash
# (A)
sed -i 's/^fleetinfo_version: .*/fleetinfo_version: "1.2.0"/' ansible/group_vars/all/vars.yml
# (B)
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo
```

Résultat attendu : `failed=0` sur les deux VM, `/health` en `1.2.0`, ligne
`... demandee=1.2.0 precedente=1.1.0 resultat=SUCCES` dans chaque journal.

**À dire / à montrer :**

- `fleetinfo_simulate_failure=true` livre une release **sans** `health.json` : nginx répond 404,
  comme pour une vraie release cassée.
- `block` : génération, bascule, contrôle `/health` ; `rescue` : rebascule vers la release N-1
  mémorisée **avant** la bascule, rechargement, revérification, échec explicite avec un message
  clair ; `always` : une ligne de journal par tentative.
- Canari + `max_fail_percentage: 0` : une version défectueuse ne dépasse jamais le premier serveur.
- Procédure complète : [RB-08](runbooks.md#rb-08-rollback-automatique-et-simulation-déchec) ;
  retour arrière manuel : [RB-02](runbooks.md#rb-02-revenir-à-une-version-précédente).

### Étape 8 : `/status` refusé sans authentification, accepté avec

**Où :** terminal B (le mot de passe est lu dans le coffre sans être affiché), puis le navigateur.

```bash
# (B)
curl -s -o /dev/null -w '%{http_code}\n' http://203.0.113.10/status
curl -s -o /dev/null -w '%{http_code}\n' -u 'exploitation:mauvais' http://203.0.113.10/status
STATUS_PASS="$(ansible-vault view group_vars/all/vault.yml | python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["vault_webserver_status_password"])')"
curl -s -u "exploitation:${STATUS_PASS}" http://203.0.113.10/status
head -n 1 group_vars/all/vault.yml
grep -n 'status_password' group_vars/all/vars.yml
```

**Résultat attendu :**

- `401`, puis `401` (mauvais mot de passe), puis la page `stub_status` (les compteurs varient) :

  ```text
  Active connections: 1
  server accepts handled requests
   12 12 12
  Reading: 0 Writing: 1 Waiting: 0
  ```

- `$ANSIBLE_VAULT;1.1;AES256` : le coffre est chiffré ;
- `38:webserver_status_password: "{{ vault_webserver_status_password }}"` : seule la référence est
  en clair ;
- dans le navigateur, `http://203.0.113.10/status` ouvre une fenêtre d'authentification.

**À dire / à montrer :**

- Mot de passe aléatoire de 24 caractères stocké dans Ansible Vault (`vault.yml`, préfixe
  `vault_`), haché dans `/etc/nginx/fleetinfo-status.htpasswd` (`apr_md5_crypt`), tâche en
  `no_log: true` ; `.vault_pass` est ignoré par Git et transmis hors Git (ADR-11).
- Rotation : [RB-05](runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).

### Étape 9 : environnement local, même `site.yml`, même résultat

**Où :** terminal A, puis B, puis le navigateur.

```bash
# (A)
cd local
docker compose up -d --wait
docker compose ps
cd ..
# (B) inventaire par défaut : le banc local
ansible-inventory --graph
ansible-playbook site.yml
```

**Résultat attendu :**

- `docker compose ps` : `fleetinfo-local-controller-1`, `fleetinfo-local-node1-1` et
  `fleetinfo-local-node2-1` en `Up`, les nœuds `(healthy)`, ports `0.0.0.0:8081->80/tcp` et
  `0.0.0.0:8082->80/tcp` ;
- `--graph` : groupe `@web` avec `node1` et `node2` ;
- `site.yml` : mêmes trois plays, mêmes tâches ; les rôles `common` et `webserver` sont déjà
  conformes, seul le déploiement fait passer les nœuds de `1.0.0` à la version de `vars.yml`
  (`1.2.0` si le déploiement sain de l'étape 7 a été fait, sinon `1.1.0`), canari `node1` puis
  `node2` ; PLAY RECAP `failed=0` ;
- `http://localhost:8081` et `http://localhost:8082` : environnement `local`, même version que sur
  le cloud, **pas** de rubrique Cloud, bandeau vert.

Variante « nœuds vierges » (si le temps le permet ou si l'examinateur la demande ; compter
quelques minutes pour l'installation des paquets) : `docker compose up -d --force-recreate --wait node1 node2`
depuis `local/`, puis `ansible-playbook site.yml`. Le controller n'est pas recréé, le terminal B
reste ouvert.

**À dire / à montrer :**

- Même `site.yml`, mêmes rôles, mêmes templates ; seuls l'inventaire (statique
  `inventories/local/hosts.yml` contre dynamique) et les `group_vars` d'inventaire diffèrent
  (ADR-01). Ouvrir côte à côte `inventories/local/group_vars/all.yml` et
  `inventories/cloud/group_vars/all.yml` : mêmes clés, autres valeurs.
- Nœuds Debian 12 avec systemd en PID 1, sshd, python3 et sudo : Ansible les gère comme des VM
  (ADR-03). Controller conteneurisé, identique pour le local et le cloud (ADR-02).

### Étape 10 : `terraform destroy`

**Où :** terminal A, depuis `socle-web-automatise/`.

```bash
# (A)
terraform -chdir=terraform destroy
# répondre : yes
gcloud compute instances list --filter="labels.app=fleetinfo"
rm -f ansible/inventories/cloud/fleet.gcp.yml
rm -rf .secrets
```

**Résultat attendu :** `Plan: 0 to add, 0 to change, 6 to destroy.`, puis
`Destroy complete! Resources: 6 destroyed.` ; `gcloud` répond `Listed 0 items.`

**À dire / à montrer :**

- Tout est reconstructible à l'identique en quelques commandes ; rien ne survit (disques en
  `auto_delete`).
- State local, acceptable pour un lab éphémère ; en entreprise : backend distant partagé,
  versionné et verrouillé (ADR-05).
- Les fichiers propres à la session (inventaire généré, identifiants copiés) sont supprimés
  ([RB-07](runbooks.md#rb-07-détruire-lenvironnement-proprement)).

---

## Après la démonstration

```bash
# (A) revenir à la version de référence du dépôt
git checkout -- ansible/group_vars/all/vars.yml
git status
```

Résultat attendu : `git status` ne signale aucune modification. Le banc local peut rester démarré
(un `ansible-playbook site.yml` le ramène en `1.0.0`) ou être arrêté
(`cd local && docker compose down`). Dans le controller, `rm -f /root/.ssh/known_hosts` oublie
les clés d'hôte des VM détruites.

---

## Plan B : démonstration intégrale en local

À utiliser si le lab ne démarre pas, si ses identifiants ne fonctionnent pas ou si le temps
restant est insuffisant. Les dix étapes sont conservées dans le même ordre ; toutes les commandes
Ansible sont identiques, sans `-i` (l'inventaire par défaut est le banc local). Les résultats
ci-dessous ont été **observés** sur le banc local le 2026-11-03, sauf mention contraire.

Préalable : `vars.yml` en `1.0.0` ; dans le terminal A, depuis `local/`,
`docker compose up -d --force-recreate --wait node1 node2` pour partir de nœuds vierges ;
terminal B ouvert dans le controller.

| Étape | Commande (local) | Résultat / à montrer |
|---|---|---|
| 1 | (A) `terraform -chdir=terraform fmt -check -recursive` puis `terraform -chdir=terraform validate` | Aucune sortie, puis `Success! The configuration is valid.` Commenter le code (`main.tf`, modules, validations de `variables.tf`, `ssh_source_ranges` sensible) et les six ressources qu'un `apply` créerait. Avec un `terraform.tfvars` renseigné et des ADC présentes sur le poste, `terraform -chdir=terraform plan` affiche `Plan: 6 to add` et `(sensitive value)` pour la plage SSH (observé hors lab). |
| 2 | (B) `ansible-inventory --graph` | `@web` avec `node1`, `node2`. Montrer `fleet.gcp.yml.example` : sur le cloud, le même groupe `web` est produit par `keyed_groups` (testé avec une réponse simulée de l'API Compute Engine et le vrai plugin : `@web`, `@env_cloud`, `@zone_us_central1_f`). |
| 3 | (B) `ansible-playbook site.yml` | Tout est `changed` au premier passage, canari `node1` puis `node2`, `failed=0`. Pages `http://localhost:8081` et `http://localhost:8082` : noms d'hôte et IP différents, environnement `local`, pas de rubrique Cloud. Facultatif (non rejoué) : `ansible-playbook site.yml --tags fleetinfo -e fleetinfo_cloud_zone=us-central1-f -e fleetinfo_cloud_machine_type=e2-small` fait apparaître la rubrique « Cloud · Google Compute Engine » (mise à jour sur place) ; relancer sans `-e` pour revenir à la page locale. |
| 4 | (B) `ansible-playbook site.yml` | `node1 : ok=39 changed=0 ... failed=0` et `node2 : ok=39 changed=0 ... failed=0`. |
| 5 | (B) `ssh -i /root/.ssh/fleet_key ansible@node1` (répondre `yes` à la première connexion), puis `head -n 2 /etc/nginx/sites-enabled/fleetinfo.conf` | Bannière `Environnement : local`, en-tête `# Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN ...` et `# Source : roles/webserver/templates/fleetinfo.conf.j2`. Mêmes fichiers à proposer qu'à l'étape 5 cloud. Si `ssh` affiche `REMOTE HOST IDENTIFICATION HAS CHANGED` (image des nœuds reconstruite depuis la répétition : nouvelles clés d'hôte), lancer `ssh-keygen -R node1` dans le controller puis recommencer. |
| 6 | (A) `vars.yml` en `1.1.0` (commande `sed` de l'étape 6) ; (B) `ansible-playbook site.yml --tags fleetinfo` | `curl -s http://localhost:8081/health` et `curl -s http://localhost:8082/health` : `"version": "1.1.0"`. |
| 7 | (B) `ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true` | `/health` en 404 (cinq lignes `FAILED - RETRYING`), `rescue` vers `1.1.0` ; `node1 : failed=1 rescued=1`, `node2` jamais touché ; site en ligne en `1.1.0` ; journal (`ansible web -b -m ansible.builtin.command -a "tail -n 2 /var/log/fleetinfo/deploy.log"`) : `hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="..."`. Puis `vars.yml` en `1.2.0` et `ansible-playbook site.yml --tags fleetinfo` : succès sur les deux nœuds. |
| 8 | (A) `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/status` ; (B) commandes de l'étape 8 en remplaçant l'IP par `node1` (`http://node1/status`) | `401` sans authentification, `401` avec un mauvais mot de passe, `200` et `stub_status` avec le bon. |
| 9 | (A) depuis `local/` : `docker compose up -d --wait` puis `docker compose ps` ; (B) `ansible-playbook site.yml`, puis `ansible-playbook site.yml --check --diff` ; montrer les deux `group_vars` d'inventaire côte à côte | Banc déjà démarré : `docker compose up` ne recrée rien, les trois conteneurs sont `Up` et les nœuds `(healthy)`. `site.yml` : `changed=0`, `failed=0` (même commande et même résultat qu'à l'étape 4) ; la simulation confirme `changed=0` : les nœuds sont conformes. Seuls l'inventaire et ses `group_vars` changent entre les environnements. Si l'examinateur le demande, ajouter `node3` ([RB-03](runbooks.md#rb-03-ajouter-ou-retirer-un-serveur), non rejoué) : aucune ligne de rôle modifiée. |
| 10 | (A) `cd local && docker compose down` | Conteneurs et réseau `fleetinfo-local_labnet` supprimés ; expliquer ce que ferait `terraform destroy` et la vérification `gcloud compute instances list` ([RB-07](runbooks.md#rb-07-détruire-lenvironnement-proprement)). |

---

## Si l'examinateur demande un runbook en direct

Runbooks rapides à dérouler sur le banc local (ou sur le cloud tant qu'il existe) :

| Demande probable | Runbook | Durée indicative |
|---|---|---|
| « Ce serveur est-il conforme ? » | [RB-06](runbooks.md#rb-06-vérifier-la-conformité-dun-serveur) : `ansible-playbook site.yml --check --diff --limit node1` | 1 min |
| « Revenez à la version précédente » | [RB-02](runbooks.md#rb-02-revenir-à-une-version-précédente), méthode (b) : `ansible-playbook rollback.yml`, puis aligner `vars.yml` | 1 min |
| « Changez le mot de passe de /status » | [RB-05](runbooks.md#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault), partie A | 2 min |
| « Modifiez la configuration nginx » | [RB-04](runbooks.md#rb-04-modifier-la-configuration-du-serveur-web) : `--check --diff`, puis application et handlers | 2 min |
| « Ajoutez un serveur » | [RB-03](runbooks.md#rb-03-ajouter-ou-retirer-un-serveur) : `vm_count = 3` (cloud) ou `node3` (local) | 3 min |
| « Détruisez l'environnement » | [RB-07](runbooks.md#rb-07-détruire-lenvironnement-proprement) | 2 min |

Questions de fond probables et décision correspondante, dans [decisions.md](decisions.md) : rôle
public `geerlingguy.nginx` (ADR-04), image des nœuds (ADR-03), state Terraform (ADR-05), accès
SSH (ADR-06), inventaire dynamique (ADR-07), absence de dossier `playbooks/` (ADR-09), reload
plutôt que restart (ADR-10), secrets (ADR-11).
