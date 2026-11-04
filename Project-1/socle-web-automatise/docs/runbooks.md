# Runbooks d'exploitation : Socle Web Automatisé

Ce document décrit, opération par opération, comment exploiter le socle au quotidien. Il
s'adresse à l'équipe qui reprend le run et suppose que l'environnement a déjà été déployé une
première fois en suivant le [README principal](../README.md) (section « Déploiement de zéro »).

Chaque runbook suit le même plan :

1. **Quand l'utiliser** : la situation qui justifie l'opération ;
2. **Prérequis** : ce qui doit être vrai avant de commencer ;
3. **Commandes** : à copier telles quelles, avec les variantes local et cloud quand elles diffèrent ;
4. **Vérifier que l'opération a réussi** : commandes de contrôle et résultat attendu ;
5. **En cas d'échec** : symptômes connus et conduite à tenir.

Documents liés : [décisions techniques](decisions.md) (ADR-01 à ADR-13),
[référence des variables](variables.md), [dépannage](troubleshooting.md),
[architecture](architecture.md), [script de démonstration](demo.md), README des rôles
([common](../ansible/roles/common/README.md), [webserver](../ansible/roles/webserver/README.md),
[fleetinfo](../ansible/roles/fleetinfo/README.md)).

> **Statut de validation.** Les résultats signalés « observé en local » ont été relevés sur le
> banc Docker Compose le 2026-11-03. L'environnement **cloud** n'a pas encore été rejoué de bout en
> bout sur un projet GCP réel (session de lab expirée) : pour le cloud, toutes les sorties
> indiquées sont des **résultats attendus**, déduits du code et des tests locaux, à confirmer lors
> de la répétition générale.

## Sommaire

| Runbook | Opération | Local | Cloud |
|---|---|:---:|:---:|
| [RB-01](#rb-01-déployer-une-nouvelle-version) | Déployer une nouvelle version de l'application | oui | oui |
| [RB-02](#rb-02-revenir-à-une-version-précédente) | Revenir manuellement à une version précédente | oui | oui |
| [RB-03](#rb-03-ajouter-ou-retirer-un-serveur) | Ajouter ou retirer un serveur | oui | oui |
| [RB-04](#rb-04-modifier-la-configuration-du-serveur-web) | Modifier la configuration du serveur web | oui | oui |
| [RB-05](#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault) | Changer le mot de passe de `/status` et le mot de passe Vault | oui | oui |
| [RB-06](#rb-06-vérifier-la-conformité-dun-serveur) | Vérifier l'état de conformité d'un serveur | oui | oui |
| [RB-07](#rb-07-détruire-lenvironnement-proprement) | Détruire l'environnement proprement | oui | oui |
| [RB-08](#rb-08-rollback-automatique-et-simulation-déchec) | Rollback automatique : simuler un échec (démonstration) | oui | oui |

---

## Conventions communes

### Où lancer les commandes

Chaque bloc de commandes commence par un commentaire qui indique où le lancer :

| Repère | Emplacement | Outils |
|---|---|---|
| `# (poste)` | Dossier `Project-1/socle-web-automatise/` du dépôt cloné, shell bash (Linux, macOS, WSL ou Git Bash sous Windows) | `git`, `docker`, `terraform`, `gcloud`, `curl`, scripts `*.sh` |
| `# (controller)` | Shell du conteneur Ansible, dossier `/workspace/ansible` (le dossier `socle-web-automatise/` du poste est monté sur `/workspace`) | `ansible`, `ansible-playbook`, `ansible-inventory`, `ansible-vault`, `ansible-lint` |
| `# (serveur)` | Session SSH ouverte sur un nœud local ou une VM GCP | lecture de fichiers, `sudo` |

Ouvrir un shell dans le controller (la commande démarre aussi `node1` et `node2`, dont il dépend) :

```bash
# (poste)
cd local
docker compose up -d --wait
docker compose exec controller bash
```

Résultat attendu : l'invite du conteneur s'affiche dans `/workspace/ansible`. Avec le Dev
Container VS Code (`.devcontainer/devcontainer.json`), le terminal s'ouvre dans `/workspace` :
faire d'abord `cd ansible`.

Sous Windows, dans PowerShell, `curl` est un alias d'`Invoke-WebRequest` : utiliser `curl.exe`,
ou lancer les commandes « poste » dans Git Bash ou WSL.

### Choisir l'environnement ciblé

- **Local** (par défaut) : `ansible.cfg` pointe sur `inventories/local/hosts.yml`. Aucune option à
  ajouter.
- **Cloud** : ajouter `-i inventories/cloud/fleet.gcp.yml` à **chaque** commande `ansible`,
  `ansible-playbook` et `ansible-inventory`. Ce fichier n'est pas versionné : il est généré sur le
  poste par `./scripts/prepare-cloud-inventory.sh` après `terraform apply` (ADR-07). Contrôle
  préalable :

  ```bash
  # (controller)
  ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
  ```

  Résultat attendu : les VM `fleetinfo-web-1`, `fleetinfo-web-2`... apparaissent dans les groupes
  `@web`, `@env_cloud` et `@zone_<zone>` (par exemple `@zone_us_central1_f`).

Le code Ansible est strictement le même dans les deux environnements (ADR-01) : seuls
l'inventaire et les `group_vars` d'inventaire (`inventories/<local|cloud>/group_vars/all.yml`)
diffèrent.

### Noms et adresses des serveurs

| Environnement | Noms d'hôte Ansible | Page d'accueil | Contrôle de santé |
|---|---|---|---|
| Local | `node1`, `node2` | `http://localhost:8081`, `http://localhost:8082` | `http://localhost:8081/health`, `http://localhost:8082/health` |
| Cloud | `fleetinfo-web-1` ... `fleetinfo-web-N` | `terraform -chdir=terraform output fleetinfo_urls` | `terraform -chdir=terraform output health_urls` |

Dans ce document, les IP publiques des VM sont représentées par des adresses de documentation
(`203.0.113.10` pour `fleetinfo-web-1`, `203.0.113.11` pour `fleetinfo-web-2`) : remplacez-les
par celles que renvoie `terraform -chdir=terraform output vm_public_ips`.

### Lire le PLAY RECAP

Exemple observé en local (second passage de `site.yml`) : `node1 : ok=39 changed=0 unreachable=0 failed=0`,
idem pour `node2`.

- `failed=0` et `unreachable=0` sur tous les hôtes : l'exécution a réussi ;
- `changed=0` : rien n'a été modifié, le serveur était déjà conforme ;
- `rescued=1` : le retour arrière automatique de Fleet Info s'est déclenché sur cet hôte
  ([RB-08](#rb-08-rollback-automatique-et-simulation-déchec)) ;
- les compteurs `ok` et `skipped` varient selon les options (`--tags`, `--check`, `--limit`) : ils
  ne sont pas un critère de réussite.

### Contrôles rapides (réutilisés par les runbooks)

```bash
# (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud

# Connectivité SSH et Python vers tous les serveurs -> "ping": "pong" pour chaque hôte
ansible web -m ansible.builtin.ping

# Réponse de /health vue depuis chaque serveur (status, version, environment, hostname, deployed_at)
ansible web -m ansible.builtin.command -a "curl -s http://127.0.0.1/health"

# Fait local : release active (version), release précédente (previous_version), date (deployed_at)
ansible web -m ansible.builtin.setup -a "filter=ansible_local"

# Releases présentes sur le disque, puis cible du lien current
ansible web -m ansible.builtin.command -a "ls /opt/fleetinfo/releases"
ansible web -m ansible.builtin.command -a "readlink /opt/fleetinfo/current"

# Dernières lignes du journal de déploiement (fichier root:adm en 0640, d'où -b)
ansible web -b -m ansible.builtin.command -a "tail -n 3 /var/log/fleetinfo/deploy.log"
```

Les commandes ad hoc fondées sur `ansible.builtin.command` affichent `CHANGED | rc=0` : c'est le
comportement normal du module `command`, qui ne sait pas qu'il n'a fait que lire. Rien n'est
modifié sur les serveurs.

Lire le mot de passe de `/status` dans le coffre sans l'afficher à l'écran (utile en partage
d'écran) :

```bash
# (controller)
STATUS_PASS="$(ansible-vault view group_vars/all/vault.yml | python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["vault_webserver_status_password"])')"
```

### Journal de déploiement

Chaque tentative réelle de déploiement ou de retour arrière ajoute une ligne à
`/var/log/fleetinfo/deploy.log` sur le serveur concerné (bloc `always` du rôle `fleetinfo`).
Lignes réelles relevées sur le banc local :

```text
2026-11-03T18:09:57Z hote=node1 type=deploiement demandee=1.1.0 precedente=1.0.0 resultat=SUCCES
2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
```

| Champ | Valeurs |
|---|---|
| date | UTC, format ISO 8601 |
| `hote` | nom d'hôte Ansible (`node1`, `fleetinfo-web-1`...) |
| `type` | `deploiement` (bascule vers une autre release), `rollback-manuel` (`rollback.yml`), `mise-a-jour-sur-place` (release active régénérée, sans bascule) |
| `demandee` / `precedente` | version demandée / version active avant l'opération (`aucune` au premier déploiement ; pour `mise-a-jour-sur-place`, les deux valeurs sont identiques) |
| `resultat` | `SUCCES` ; `ECHEC_ROLLBACK_OK` (échec, version précédente restaurée et saine) ; `ECHEC_ROLLBACK_KO` (échec, et la version précédente ne répond pas : incident) ; `ECHEC_SANS_ROLLBACK` (échec sans version vers laquelle revenir : premier déploiement ou mise à jour sur place) |
| `detail` | cause de l'échec (nom de la tâche en erreur et message), uniquement en cas d'échec |

Un passage sur un serveur déjà conforme (`changed=0`) n'écrit **aucune** ligne. Une simulation
(`--check`) n'écrit jamais dans le journal.

### Fichiers utiles sur les serveurs

| Chemin | Contenu | Produit par |
|---|---|---|
| `/opt/fleetinfo/releases/<version>/` | `index.html` et `health.json` d'une release | rôle `fleetinfo` (templates) |
| `/opt/fleetinfo/current` | lien symbolique vers la release active (racine servie par nginx) | rôle `fleetinfo` |
| `/etc/ansible/facts.d/fleetinfo.fact` | release active, précédente, date de déploiement (relu par Ansible : `ansible_local.fleetinfo`) | rôle `fleetinfo` (template) |
| `/var/log/fleetinfo/deploy.log` | journal des déploiements | rôle `fleetinfo` |
| `/etc/nginx/sites-enabled/fleetinfo.conf` | site Fleet Info (`/`, `/health`, `/status`) | rôle `webserver` (template) |
| `/etc/nginx/fleetinfo-status.htpasswd` | compte autorisé sur `/status` (mot de passe haché) | rôle `webserver` (module `htpasswd`) |
| `/var/log/nginx/fleetinfo.access.log`, `/var/log/nginx/fleetinfo.error.log` | journaux du site | nginx |
| `/etc/nginx/nginx.conf` | configuration générale de nginx | rôle public `geerlingguy.nginx` (template enveloppé par le rôle `webserver`, avec en-tête) |
| `/etc/motd` | bannière de connexion | rôle `common` (template) |

Les fichiers produits par un **template de nos rôles** (marqués « template » ci-dessus) portent
en tête l'en-tête `Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN ...`
(commentaire `#` ou HTML, ou clé `_ansible_managed` pour les fichiers JSON), suivi du template
source. `/etc/nginx/nginx.conf` porte lui aussi l'en-tête, ajouté par l'enveloppe
`roles/webserver/templates/nginx.conf.j2` autour du template du rôle public. Seul le fichier
`htpasswd` (produit par un module, pas par un template) n'en a pas. Ne modifiez
jamais ces fichiers sur le serveur : passez par le dépôt Git, puis relancez `site.yml`.

---

## RB-01 Déployer une nouvelle version

### Quand l'utiliser

- Une nouvelle release de Fleet Info doit être livrée (par exemple passage de `1.0.0` à `1.1.0`).
- Les templates de l'application (`roles/fleetinfo/templates/index.html.j2`, `health.json.j2`)
  ont été modifiés : livrez-les **toujours** sous un nouveau numéro de version. Rejouer le même
  numéro régénère la release active sur place (`type=mise-a-jour-sur-place`), sans retour arrière
  possible en cas d'échec.

### Prérequis

- Controller démarré, `.vault_pass` présent à la racine du socle, dépendances Galaxy installées
  (automatique au démarrage du controller ; vérification : `ansible-galaxy install -r requirements.yml`).
- Serveurs joignables (`ansible web -m ansible.builtin.ping`) et servant une version saine :
  contrôlez la version active avec `ansible web -m ansible.builtin.command -a "curl -s http://127.0.0.1/health"`.
- Numéro de version au format `X.Y.Z`, différent de la version active.
- Cloud : inventaire dynamique prêt (voir [Choisir l'environnement ciblé](#choisir-lenvironnement-ciblé))
  et IP publique du poste toujours autorisée en SSH (`ssh_source_ranges`).
- Recommandé : livrer d'abord sur le banc local.

### Commandes

1. Modifier **la seule** variable de version, dans `ansible/group_vars/all/vars.yml` (commune aux
   deux environnements) : `fleetinfo_version: "1.1.0"`. À la main, ou :

   ```bash
   # (poste) sous macOS : sed -i '' ...
   sed -i 's/^fleetinfo_version: .*/fleetinfo_version: "1.1.0"/' ansible/group_vars/all/vars.yml
   git diff ansible/group_vars/all/vars.yml
   ```

   Résultat attendu : une seule ligne modifiée, `-fleetinfo_version: "1.0.0"` /
   `+fleetinfo_version: "1.1.0"`. Ne modifiez pas `roles/fleetinfo/defaults/main.yml` : c'est une
   valeur de secours, toujours écrasée par `vars.yml`.

   Facultatif : ajouter une note de version dans `fleetinfo_release_notes`
   (`ansible/roles/fleetinfo/defaults/main.yml`, ou surcharge dans `group_vars/all/vars.yml`).
   Une version absente de ce catalogue reste déployable ; la rubrique « Notes de version » de
   la page est alors omise.

2. Simuler le déploiement (recommandé) :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags fleetinfo --check --diff
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo --check --diff
   ```

   Résultat attendu (observé en local avec une nouvelle version) : `failed=0` ; la création de la
   release `1.1.0`, la génération de la page et de `health.json`, la bascule du lien `current` et
   la mise à jour du fait local sont annoncées `changed`. Le contrôle `/health` est sauté en
   simulation.

3. Déployer :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags fleetinfo
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo
   ```

   `--tags fleetinfo` ne joue que le déploiement applicatif. Sans `--tags`, `site.yml` réapplique
   aussi les rôles `common` et `webserver` (sans effet s'ils sont conformes) : c'est le choix le
   plus sûr si d'autres modifications du dépôt n'ont pas encore été appliquées.

   Déroulé : le play `Déployer l'application Fleet Info` traite d'abord **un seul serveur**
   (canari : `node1` en local, en principe `fleetinfo-web-1` sur le cloud), puis tous les autres
   (`serial: [1, "100%"]`, `max_fail_percentage: 0`, ADR-08). Sur chaque serveur : génération de
   `releases/1.1.0/`, bascule atomique du lien `current`, tâche `Interroger /health jusqu'à obtenir la version 1.1.0`
   (statut `200`, `status=ok`, `version=1.1.0`), mise à jour du fait local, ligne de journal, puis
   ménage des anciennes releases : au-delà de `fleetinfo_keep_releases: 3`, la plus ancienne est
   supprimée, la release active et la précédente étant toujours protégées (observé en local : au
   déploiement d'une 4e release, `1.3.0`, la release `1.0.0` a été supprimée).

4. Versionner la livraison :

   ```bash
   # (poste)
   git add ansible/group_vars/all/vars.yml
   git commit -m "feat: livraison de Fleet Info 1.1.0"
   git push
   ```

N'utilisez pas `-e fleetinfo_version=...` pour une livraison réelle : la valeur passée en ligne de
commande n'est pas tracée dans Git, et le `site.yml` suivant, lancé sans `-e`, reviendrait à la
version de `vars.yml`. Le `-e` est réservé aux tests et à la démonstration.

### Vérifier que l'opération a réussi

1. PLAY RECAP : `failed=0` et `unreachable=0` sur tous les serveurs.
2. `/health` renvoie la nouvelle version sur chaque serveur :

   ```bash
   # (poste) local
   curl -s http://localhost:8081/health
   curl -s http://localhost:8082/health
   # (poste) cloud : une URL par VM
   terraform -chdir=terraform output health_urls
   curl -s http://203.0.113.10/health
   ```

   Résultat attendu : JSON contenant `"status": "ok"` et `"version": "1.1.0"` (observé en local
   sur les deux nœuds ; résultat attendu identique sur le cloud, avec `"environment": "cloud"`).

3. Page d'accueil (navigateur) : badge `Fleet Info v1.1.0`, rubrique « Déploiement » avec
   `Version 1.1.0`, `Version précédente 1.0.0`, la date du déploiement et la note de version.
4. Journal :

   ```bash
   # (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud
   ansible web -b -m ansible.builtin.command -a "tail -n 1 /var/log/fleetinfo/deploy.log"
   ```

   Résultat attendu sur chaque serveur (forme observée en local) :
   `<date> hote=node1 type=deploiement demandee=1.1.0 precedente=1.0.0 resultat=SUCCES`.

5. Idempotence : relancer la même commande de déploiement. Résultat attendu : `changed=0` sur tous
   les serveurs, aucune nouvelle ligne de journal.

### En cas d'échec

| Symptôme | Cause probable | Action |
|---|---|---|
| `fleetinfo_version="..." n'est pas une version X.Y.Z valide` | Format incorrect (`v1.1`, `1.1`...) | Corriger la valeur dans `vars.yml` (entre guillemets) et relancer. Rien n'a été modifié. |
| `FAILED - RETRYING: ... Interroger /health ...`, puis `ÉCHEC du déploiement de Fleet Info ... Retour arrière effectué ...` ; `rescued=1` sur le canari | La release ne passe pas le contrôle de santé | Le retour arrière automatique a fonctionné : le canari est revenu à N-1, les autres serveurs n'ont pas reçu la version. Lire la cause dans le message et dans le journal (`detail=`), corriger, relancer. Voir [RB-08](#rb-08-rollback-automatique-et-simulation-déchec). |
| `resultat=ECHEC_ROLLBACK_KO` dans le journal | La version précédente ne répond pas non plus sur `/health` | Incident : sur le serveur, `sudo systemctl status nginx` et `sudo nginx -t`, puis rebasculer vers une release saine avec [RB-02](#rb-02-revenir-à-une-version-précédente) méthode (b) et `-e fleetinfo_rollback_version=X.Y.Z`. |
| `UNREACHABLE!` | SSH impossible (VM arrêtée, IP du poste changée, clé) | `ansible web -m ansible.builtin.ping` ; voir [dépannage](troubleshooting.md) (erreur n° 8 : timeout SSH, clé d'hôte changée). |
| `Mot de passe Vault introuvable : créer socle-web-automatise/.vault_pass ...` (controller) ou `The vault password file ... was not found` | Fichier du mot de passe Vault absent | Créer `.vault_pass` à la racine du socle (README, [Mot de passe Ansible Vault](../README.md#mot-de-passe-ansible-vault)). |
| Version inchangée après un passage réussi | Option `-e fleetinfo_version` passée, ou mauvais inventaire | Relancer sans `-e`, avec le bon `-i`. |

---

## RB-02 Revenir à une version précédente

Deux méthodes existent. Utilisez la méthode (a) par défaut ; réservez la méthode (b) à l'urgence.

| | (a) Méthode « Git » (recommandée) | (b) Méthode d'urgence : `rollback.yml` |
|---|---|---|
| Principe | Remettre l'ancienne valeur de `fleetinfo_version` et relancer `site.yml` | Rebasculer `current` vers une release **déjà présente** sur le disque, sans la régénérer |
| Traçabilité | Commit Git + journal des serveurs | Journal des serveurs ; `vars.yml` à aligner ensuite |
| Release purgée du disque | Régénérée | Impossible |
| Garde-fous | Canari, contrôle `/health`, retour arrière automatique, journal | Canari, contrôle `/health`, retour arrière automatique, journal |

### Quand l'utiliser

- La version livrée fonctionne techniquement (`/health` répond) mais pose un problème fonctionnel :
  il faut revenir à la version précédente.
- (b) uniquement : il faut rétablir le service immédiatement, sans attendre une modification du
  dépôt (dépôt inaccessible, revue impossible dans le délai).

Si le déploiement a échoué sur `/health`, il n'y a rien à faire : le retour arrière automatique a
déjà eu lieu ([RB-08](#rb-08-rollback-automatique-et-simulation-déchec)).

### Prérequis

- Prérequis de [RB-01](#rb-01-déployer-une-nouvelle-version) (controller, Vault, connectivité,
  inventaire cloud le cas échéant).
- Connaître la version cible et l'état de chaque serveur :

  ```bash
  # (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud
  ansible web -m ansible.builtin.setup -a "filter=ansible_local"
  ansible web -m ansible.builtin.command -a "ls /opt/fleetinfo/releases"
  ```

  Résultat : `ansible_local.fleetinfo.version` (release active) et `previous_version` (release
  N-1 mémorisée), puis la liste des releases présentes (en principe trois au plus,
  `fleetinfo_keep_releases` ; une release en échec peut s'y ajouter, le ménage n'ayant lieu qu'après
  un déploiement réussi).
- (b) uniquement : la release cible doit être présente **et complète** (`health.json` présent) sur
  chaque serveur.

### Commandes

**(a) Méthode « Git »**

1. Remettre l'ancienne version dans `ansible/group_vars/all/vars.yml` (par exemple de `1.2.0` à
   `1.1.0`), à la main ou en annulant le commit de livraison :

   ```bash
   # (poste) retrouver le commit de livraison puis l'annuler
   git log --oneline -- ansible/group_vars/all/vars.yml
   git revert <commit_de_livraison_1.2.0>
   ```

2. Relancer le déploiement :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags fleetinfo
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo
   ```

   Résultat attendu : la release `1.1.0` est **régénérée** depuis les templates (recréée si elle
   avait été purgée), le lien `current` bascule, `/health` est contrôlé ; la page affiche une
   nouvelle date de déploiement et `Version précédente 1.2.0`.

3. Pousser le commit (`git push`).

**(b) Méthode d'urgence : `rollback.yml`**

```bash
# (controller) local : retour vers la release N-1 mémorisée sur chaque serveur
ansible-playbook rollback.yml
# (controller) local : retour vers une version précise, présente sur le disque
ansible-playbook rollback.yml -e fleetinfo_rollback_version=1.0.0

# (controller) cloud : mêmes commandes avec l'inventaire dynamique
ansible-playbook -i inventories/cloud/fleet.gcp.yml rollback.yml
ansible-playbook -i inventories/cloud/fleet.gcp.yml rollback.yml -e fleetinfo_rollback_version=1.0.0
```

Le play `Revenir à une version précédente de Fleet Info` traite le canari puis les autres
serveurs. Sur chaque serveur : `Déterminer la version cible du retour arrière`, vérification de la
présence de `releases/<cible>/health.json`, puis `Rebasculer sans régénération vers la release <cible>` :
bascule de `current`, contrôle `/health`, mise à jour du fait local, ligne de journal
`type=rollback-manuel`. En cas d'échec du contrôle, le même `rescue` qu'au déploiement rebascule
vers la release de départ.

Points d'attention :

- **Rejouer `rollback.yml` rebascule de nouveau.** La release quittée devient la « précédente » :
  un second `ansible-playbook rollback.yml` revient à la version de départ (aller-retour entre les
  deux dernières releases ; observé en local : `1.2.0 -> 1.1.0 -> 1.2.0`). Pour une cible stable,
  passez `-e fleetinfo_rollback_version=X.Y.Z`.
- Si les serveurs n'ont pas tous la même release N-1 mémorisée (déploiement partiel), forcez la
  même cible pour tous avec `-e fleetinfo_rollback_version=X.Y.Z`.
- Ne passez jamais `-e fleetinfo_version=...` à `rollback.yml` : une extra-var l'emporterait sur
  la cible calculée par le rôle. Le play s'arrête alors avant toute bascule, avec
  `Retour arrière manuel : ne pas passer -e fleetinfo_version (X) ; utiliser -e fleetinfo_rollback_version=X.Y.Z pour choisir la version cible.`
  (vérifié le 2026-11-04).
- **Ensuite, alignez `vars.yml`** sur la version restaurée et committez. Sinon le prochain
  `site.yml` redéploierait la version que vous venez de quitter.
- **Date affichée** : la release n'étant pas régénérée, la page et `/health` gardent la date (et la
  « version précédente ») de **leur déploiement initial**. Le fait local, lui, enregistre la date du
  retour arrière. Le premier `site.yml` suivant (avec `vars.yml` aligné) régénère alors la page
  sur place avec ces valeurs (`changed=3`, ligne `type=mise-a-jour-sur-place` dans le journal) ;
  le passage d'après revient à `changed=0` (observé sur le banc local le 2026-11-04).

### Vérifier que l'opération a réussi

1. PLAY RECAP : `failed=0`, `unreachable=0`.
2. Version servie :

   ```bash
   # (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud
   ansible web -m ansible.builtin.command -a "curl -s http://127.0.0.1/health"
   ansible web -m ansible.builtin.command -a "readlink /opt/fleetinfo/current"
   ```

   Résultat attendu : `"version": "1.1.0"` et `/opt/fleetinfo/releases/1.1.0` sur chaque serveur.
3. Journal (`tail -n 1`, voir [Contrôles rapides](#contrôles-rapides-réutilisés-par-les-runbooks)) :
   - (a) `type=deploiement demandee=1.1.0 precedente=1.2.0 resultat=SUCCES` ;
   - (b) `type=rollback-manuel demandee=1.1.0 precedente=1.2.0 resultat=SUCCES`.
4. (b) uniquement : `git diff ansible/group_vars/all/vars.yml` montre `fleetinfo_version` aligné
   sur la version restaurée, avant le commit.

### En cas d'échec

| Symptôme | Cause | Action |
|---|---|---|
| `Aucune version précédente valide n'est mémorisée sur <hôte> ("") : préciser la cible avec -e fleetinfo_rollback_version=X.Y.Z` | Un seul déploiement réussi sur ce serveur (pas de N-1 mémorisée) | Préciser la cible : `-e fleetinfo_rollback_version=X.Y.Z`. |
| `La release X.Y.Z est absente ou incomplète (pas de health.json) dans /opt/fleetinfo/releases. Releases présentes : ...` | Release purgée par le ménage, ou release cassée (par exemple celle d'une démonstration d'échec) | Choisir une release de la liste affichée, ou utiliser la méthode (a), qui régénère la release. |
| Échec du contrôle `/health` après la bascule, `rescued=1` | La release cible ne répond pas correctement | Le `rescue` a rebasculé vers la release de départ (`resultat=ECHEC_ROLLBACK_OK`) : le service est dans l'état d'avant l'opération. Diagnostiquer nginx et la release cible ([dépannage](troubleshooting.md)). |
| Le `site.yml` suivant redéploie la version quittée | `vars.yml` non aligné après (b) | Aligner `fleetinfo_version`, committer, relancer. |

---

## RB-03 Ajouter ou retirer un serveur

### Quand l'utiliser

- Augmenter ou réduire la capacité du parc web.
- Recréer un serveur défaillant (cloud).
- Reproduire en local une situation à N serveurs.

### Prérequis

- Cloud : poste qui détient le state Terraform (`terraform/terraform.tfstate`, state local,
  ADR-05) et le `terraform/terraform.tfvars` de la session en cours, identifiants gcloud valides,
  quota du lab suffisant. `vm_count` est borné entre 2 et 10 par une validation ; le socle en
  attend au moins 2.
- Local : ports hôte libres pour les nouveaux nœuds (8083, 8084...).
- Le code Ansible **n'est jamais modifié** : sur le cloud, rien à changer côté Ansible ; en local,
  seul l'inventaire statique `inventories/local/hosts.yml` change.

### Commandes

**Cloud : ajouter une VM (2 vers 3)**

1. Dans `terraform/terraform.tfvars`, passer `vm_count = 3`.
2. Appliquer :

   ```bash
   # (poste)
   terraform -chdir=terraform plan
   terraform -chdir=terraform apply
   ```

   Résultat attendu : `Plan: 1 to add, 0 to change, 0 to destroy.` (VM `fleetinfo-web-3`, mêmes
   labels et même tag réseau que les autres), puis `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`
3. L'inventaire dynamique découvre la VM seul (filtre `labels.app = fleetinfo` et
   `status = RUNNING`) ; inutile de relancer `prepare-cloud-inventory.sh`, le projet n'a pas
   changé. Attendre environ une minute (création de l'utilisateur `ansible` par l'agent invité GCE),
   puis :

   ```bash
   # (controller)
   ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml
   ```

   Pour ne configurer que la nouvelle VM : ajouter `--limit fleetinfo-web-3`.

**Cloud : retirer une VM (3 vers 2)**

1. Dans `terraform/terraform.tfvars`, repasser `vm_count = 2`.
2. Appliquer :

   ```bash
   # (poste)
   terraform -chdir=terraform plan
   terraform -chdir=terraform apply
   ```

   Résultat attendu : `Plan: 0 to add, 0 to change, 1 to destroy.` Avec `count`, Terraform
   supprime toujours les VM de **plus fort indice** (`fleetinfo-web-3`, puis `-2`...) ; on ne peut
   pas choisir la VM retirée en changeant `vm_count`. Aucune action Ansible n'est nécessaire : la VM
   disparaît de l'inventaire au prochain appel.

**Cloud : remplacer une VM précise** (par exemple `fleetinfo-web-1` défaillante), sans changer
leur nombre :

```bash
# (poste) l'indice [0] correspond à fleetinfo-web-1
terraform -chdir=terraform apply -replace='module.compute.google_compute_instance.this[0]'
# (controller) la VM recréée est vierge : la configurer entièrement
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --limit fleetinfo-web-1
```

**Local : ajouter un nœud (`node3`)**

1. Dans `local/docker-compose.yml`, décommenter le service `node3` (il réutilise l'ancre
   `x-node`) et le déclarer dans le `depends_on` du controller :

   ```yaml
   services:
     controller:
       # ...
       depends_on:
         node1:
           condition: service_healthy
         node2:
           condition: service_healthy
         node3:
           condition: service_healthy

     node3:
       <<: *node
       hostname: node3
       ports:
         - "8083:80"
   ```

2. Dans `ansible/inventories/local/hosts.yml`, ajouter l'hôte :

   ```yaml
   all:
     children:
       web:
         hosts:
           node1:
           node2:
           node3:
   ```

3. Démarrer le nœud puis le configurer :

   ```bash
   # (poste)
   cd local
   docker compose up -d --build --wait
   docker compose exec controller bash
   # (controller)
   ansible-inventory --graph
   ansible-playbook site.yml
   ```

   Si Compose recrée le controller à cette occasion, c'est sans conséquence : la clé SSH est
   recopiée par l'entrypoint et les dépendances Galaxy sont dans le dossier monté. Les nœuds
   existants gardent leur configuration (l'image, construite depuis le cache, est inchangée).

**Local : retirer un nœud**

1. Retirer `node3:` de `ansible/inventories/local/hosts.yml`.
2. Recommenter le service `node3` et son entrée `depends_on` dans `local/docker-compose.yml`.
3. Supprimer le conteneur devenu orphelin :

   ```bash
   # (poste) depuis local/
   docker compose up -d --wait --remove-orphans
   ```

### Vérifier que l'opération a réussi

- Cloud, ajout (résultats attendus) :
  - `terraform -chdir=terraform output vm_names` liste `fleetinfo-web-1`, `-2`, `-3` ;
  - `ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph` montre la nouvelle VM dans
    `@web`, `@env_cloud` et `@zone_<zone>` ;
  - PLAY RECAP : la nouvelle VM a `changed` > 0 et `failed=0` ; les VM existantes ont `changed=0` ;
  - `curl -s http://<IP de fleetinfo-web-3>/health` renvoie `"status": "ok"` et la version de
    `vars.yml` (IP : `terraform -chdir=terraform output vm_public_ips`) ;
  - un second `site.yml` donne `changed=0` partout.
- Cloud, retrait : `gcloud compute instances list --filter="labels.app=fleetinfo"` ne liste plus
  la VM ; `--graph` non plus ; `terraform -chdir=terraform plan` affiche
  `No changes. Your infrastructure matches the configuration.`
- Local, ajout : `docker compose ps` montre `fleetinfo-local-node3-1` en `(healthy)` avec
  `0.0.0.0:8083->80/tcp` ; `curl -s http://localhost:8083/health` renvoie `"hostname": "node3"` ;
  la page `http://localhost:8083` s'affiche ; second `site.yml` : `changed=0`.
- Local, retrait : `docker compose ps` ne liste plus que `controller`, `node1`, `node2` ;
  `ansible-inventory --graph` ne montre plus `node3`.

### En cas d'échec

| Symptôme | Cause | Action |
|---|---|---|
| Nouvelle VM absente de `--graph` | VM pas encore `RUNNING`, ou label `app` différent de `fleetinfo` | Attendre quelques secondes ; `gcloud compute instances list --filter="labels.app=fleetinfo"`. |
| `Permission denied (publickey)` juste après la création | L'agent invité GCE n'a pas encore créé l'utilisateur `ansible` | Attendre une minute et relancer `site.yml`. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key verification failed.` | IP éphémère déjà connue, attribuée à une autre VM | Dans le controller : `ssh-keygen -R <IP>`, puis relancer. |
| Erreur de quota ou de type de machine | Limites du lab | Réduire `vm_count` ou choisir un type autorisé (`machine_type`). |
| `vm_count doit être un entier entre 2 et 10 (le socle exige au moins 2 VM).` | Validation Terraform | Corriger la valeur. |
| `Bind for 0.0.0.0:8083 failed: port is already allocated` | Port hôte déjà utilisé | Choisir un autre port hôte dans `docker-compose.yml`. |
| `Could not resolve hostname node3` | Hôte déclaré dans `hosts.yml` mais service non démarré | Vérifier le service `node3` dans `docker-compose.yml`, puis `docker compose up -d --wait`. |

---

## RB-04 Modifier la configuration du serveur web

### Quand l'utiliser

- Restreindre l'accès à `/status` à certaines plages IP, en plus du mot de passe
  (`webserver_status_allowed_networks`).
- Ajuster la configuration générale de nginx (`/etc/nginx/nginx.conf`) gérée par le rôle public
  `geerlingguy.nginx` : variables `nginx_*`, par exemple `nginx_client_max_body_size`,
  `nginx_keepalive_timeout`, `nginx_worker_connections`.
- Changer le port HTTP du site (`socle_http_port`).

Pour le mot de passe de `/status`, voir [RB-05](#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).

### Prérequis

- Savoir **où** définir la variable (précédence Ansible, détail dans [variables.md](variables.md)) :
  - pour les deux environnements : `ansible/group_vars/all/vars.yml` ;
  - pour un seul environnement : `ansible/inventories/<local|cloud>/group_vars/all.yml`, **à
    condition que la variable ne soit pas aussi définie dans `group_vars/all/vars.yml`**, qui
    l'emporte sur les `group_vars/all` d'inventaire.
- `nginx_remove_default_vhost`, `nginx_vhosts` et `nginx_server_tokens` sont fixées dans
  `ansible/roles/webserver/meta/main.yml` (variables de la dépendance `geerlingguy.nginx`, de
  précédence supérieure aux `group_vars`) : une valeur posée dans les `group_vars` n'a aucun effet
  sur elles, il faut les modifier à cet endroit.
- Tester d'abord sur le banc local.

### Commandes

1. Modifier la variable. Exemples :

   ```yaml
   # ansible/inventories/cloud/group_vars/all.yml : /status réservé au sous-réseau et à l'IP
   # publique du poste de l'opérateur (exemple 203.0.113.50 ; valeur réelle : curl -4 -s https://ifconfig.me)
   webserver_status_allowed_networks:
     - "10.10.0.0/24"
     - "203.0.113.50/32"
   ```

   ```yaml
   # ansible/group_vars/all/vars.yml : réglage de nginx.conf (rôle geerlingguy.nginx)
   nginx_client_max_body_size: "16m"
   ```

2. Simuler et lire le diff **avant** d'appliquer :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags webserver --check --diff
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags webserver --check --diff
   ```

   Exemple de sortie (extrait, `webserver_status_allowed_networks: ["203.0.113.50/32"]`) :

   ```text
   TASK [webserver : Déployer la configuration du site Fleet Info] ****************
   --- before: /etc/nginx/sites-enabled/fleetinfo.conf
   +++ after: /root/.ansible/tmp/.../fleetinfo.conf.j2
   @@ ... @@
        location = /status {
            stub_status;
   +        allow 203.0.113.50/32;
   +        deny all;
            auth_basic "Fleet Info - statut technique";

   changed: [node1]

   RUNNING HANDLER [webserver : Valider la configuration nginx] *******************
   skipping: [node1]
   ```

   En simulation, le handler de validation est notifié mais sauté (`skipping`), rien n'est écrit
   ni rechargé ; `failed=0`.

3. Appliquer :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags webserver
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags webserver
   ```

   Chaîne de handlers (ADR-10), exécutée à la fin du play `Configurer le serveur web nginx` :
   - site Fleet Info modifié : `Déployer la configuration du site Fleet Info` (`changed`), puis
     `RUNNING HANDLER [webserver : Valider la configuration nginx]` (`nginx -t`), puis
     `RUNNING HANDLER [webserver : Recharger nginx]` (reload, sans coupure des connexions) ;
     observé en local avec `webserver_status_allowed_networks` ;
   - `nginx.conf` modifié (variables `nginx_*`) : la tâche `Copy nginx configuration in place.` du
     rôle public valide le nouveau fichier avec `nginx -t` **avant** de le poser, puis
     `RUNNING HANDLER [geerlingguy.nginx : reload nginx]`.

   Une modification qui ne touche que la page d'accueil (par exemple `-e fleetinfo_environment=demo`)
   ne déclenche aucun handler nginx (observé en local).

**Cas particulier : changer le port HTTP (`socle_http_port`)**

Le port est défini une seule fois dans `ansible/group_vars/all/vars.yml` ; nginx y écoute
(`webserver_listen_port`) et le contrôle de santé l'interroge (`fleetinfo_health_port`). Il doit
rester cohérent avec l'extérieur, qui n'est pas géré par Ansible :

1. `ansible/group_vars/all/vars.yml` : `socle_http_port: 8080`.
2. Cloud : `http_port = 8080` dans `terraform/terraform.tfvars`, puis
   `terraform -chdir=terraform apply` (résultat attendu : `Plan: 0 to add, 1 to change, 0 to destroy.`,
   la règle `fleetinfo-vpc-allow-http` est modifiée sur place). Les outputs `fleetinfo_urls` et
   `health_urls` incluent alors le port (`http://<IP>:8080/`).
3. Local : dans `local/docker-compose.yml`, publier le nouveau port des conteneurs
   (`"8081:8080"`, `"8082:8080"`), puis `docker compose up -d --wait` depuis `local/`. Les nœuds
   sont **recréés** (conteneurs neufs, donc vierges) : relancez un `site.yml` complet, sans `--tags`.
4. `ansible-playbook site.yml` (local) et `ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml` (cloud).

Côté Ansible, le changement de port a été rejoué sur le banc local le 2026-11-04 avec
`-e socle_http_port=8080` (sans republier les ports Docker) : validation puis rechargement de
nginx, contrôle `/health` réussi sur 8080, puis retour au port 80 de la même façon et `changed=0`.

Ce changement provoque une **courte interruption** (résultat déduit du code, non rejoué) : sur le
cloud, entre l'`apply` (le firewall n'ouvre plus que le nouveau port) et le rechargement de nginx
par `site.yml` (qui écoute encore sur l'ancien) ; en local, jusqu'à la fin du `site.yml` qui
reconfigure les nœuds recréés. Les commandes de contrôle qui visent le port 80
(`curl -s http://127.0.0.1/health` des [Contrôles rapides](#contrôles-rapides-réutilisés-par-les-runbooks))
doivent alors préciser le port : `http://127.0.0.1:8080/health`.

### Vérifier que l'opération a réussi

1. PLAY RECAP : `failed=0` ; les handlers `Valider la configuration nginx` puis `Recharger nginx`
   (ou `reload nginx` pour `nginx.conf`) apparaissent une fois.
2. Configuration valide et service actif :

   ```bash
   # (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud
   ansible web -b -m ansible.builtin.command -a "nginx -t"
   ansible web -m ansible.builtin.command -a "systemctl is-active nginx"
   ```

   Résultat attendu : `nginx: configuration file /etc/nginx/nginx.conf test is successful` et
   `active` sur chaque serveur.
3. Effet fonctionnel, par exemple pour le filtrage de `/status` (ici sur la VM `fleetinfo-web-1`,
   `203.0.113.10`) :
   `curl -s -o /dev/null -w '%{http_code}\n' http://203.0.113.10/status` renvoie `403` depuis une
   IP non autorisée ; depuis une IP autorisée, `401` sans mot de passe et `200` avec
   ([RB-05](#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault)).
4. Second passage de la même commande : `changed=0`, **aucun** handler exécuté (observé en local).

### En cas d'échec

**Configuration du site invalide.** Comportement observé en local le 2026-11-04 avec
`-e webserver_listen_port=99999` :

- `Déployer la configuration du site Fleet Info` **échoue avant écriture** : son option
  `validate:` teste le fichier candidat dans une configuration minimale (`nginx -t -q`) et
  affiche l'erreur, par exemple
  `[emerg] invalid port in "99999" of the "listen" directive` ;
- le fichier en place (`/etc/nginx/sites-enabled/fleetinfo.conf`) n'est **pas** modifié et aucun
  handler n'est notifié : nginx continue de servir sa configuration, le site reste en ligne ;
- le serveur est en échec (`failed=1`) : le play de déploiement de Fleet Info ne s'exécute pas
  pour lui.

Conduite à tenir :

1. Lire l'erreur `nginx` affichée par la tâche (ligne et directive fautives).
2. Corriger la variable (ou annuler le commit), puis relancer
   `ansible-playbook site.yml --tags webserver` : le template est validé, écrit, puis la chaîne
   de handlers valide la configuration complète et recharge nginx (observé en local).
3. Contrôler `nginx -t` comme ci-dessus.

Si le fichier passe la validation unitaire mais que la configuration **complète** est invalide
(conflit avec un autre fichier inclus, cas improbable avec un seul site), c'est le handler
`Valider la configuration nginx` qui échoue : `Recharger nginx` n'est jamais exécuté et nginx
garde sa configuration en mémoire. Corriger puis relancer de la même façon.

Une valeur `nginx_*` invalide, elle, est refusée **avant** l'écriture de `nginx.conf` (option
`validate` du rôle public) : la tâche échoue, l'ancien fichier reste en place.

Autres cas :

| Symptôme | Cause | Action |
|---|---|---|
| La nouvelle valeur n'est pas prise en compte pour un seul environnement | La variable est aussi définie dans `group_vars/all/vars.yml`, qui l'emporte | La définir à un seul endroit. |
| `nginx_server_tokens` (ou `nginx_vhosts`, `nginx_remove_default_vhost`) sans effet | Paramètres fixés dans `roles/webserver/meta/main.yml` | Modifier `meta/main.yml`. |
| `nginx: [emerg] a duplicate default server` | Site `default` de Debian réactivé | Garder `nginx_remove_default_vhost: true` (voir [dépannage](troubleshooting.md), erreur n° 7). |
| Site injoignable après un changement de port | Firewall GCP ou ports Compose non alignés | Aligner `http_port` (Terraform) et `ports` (Compose) sur `socle_http_port`. |
| `403` sur `/status` pour l'opérateur | Son IP n'est pas dans `webserver_status_allowed_networks` | Ajouter la plage, relancer `--tags webserver`. |

---

## RB-05 Changer le mot de passe de /status et le mot de passe Vault

Deux secrets distincts :

| Secret | Où il vit | Qui l'utilise |
|---|---|---|
| Mot de passe de `/status` (compte `exploitation`, `webserver_status_user`) | `vault_webserver_status_password` dans `ansible/group_vars/all/vault.yml` (chiffré), référencé par `webserver_status_password` dans `vars.yml` | nginx (`/etc/nginx/fleetinfo-status.htpasswd`, haché en `apr_md5_crypt`) |
| Mot de passe du coffre Vault | fichier `socle-web-automatise/.vault_pass` (non versionné), lu dans le controller par `/usr/local/bin/fleet-vault-pass` (`ANSIBLE_VAULT_PASSWORD_FILE`) et hors controller via `vault_password_file = ../.vault_pass` (`ansible.cfg`) | Ansible, pour déchiffrer `vault.yml` |

### Quand l'utiliser

- Rotation périodique, départ d'une personne qui connaissait un secret, suspicion de fuite.
- Après une fuite du **mot de passe Vault**, faites les deux opérations : l'historique Git contient
  les anciennes versions de `vault.yml`, toujours déchiffrables avec l'ancien mot de passe Vault ;
  seul un changement du mot de passe `/status` rend ces anciennes versions inutiles.

### Prérequis

- Controller démarré, `.vault_pass` actuel valide :
  `ansible-vault view group_vars/all/vault.yml > /dev/null && echo OK` affiche `OK`.
- Un moyen de transmettre un secret hors Git à l'équipe (gestionnaire de mots de passe de
  l'équipe, canal chiffré) ; jamais par ticket, e-mail ou messagerie en clair.
- Le coffre est commun aux deux environnements : prévoyez de réappliquer le changement de mot de
  passe `/status` **en local et sur le cloud**.

### Commandes

**A. Changer le mot de passe de `/status`**

1. Générer un nouveau mot de passe (24 caractères alphanumériques aléatoires, comme l'actuel) :

   ```bash
   # (controller)
   python3 -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for _ in range(24)))'
   ```

2. Éditer le coffre et remplacer la valeur de `vault_webserver_status_password` :

   ```bash
   # (controller)
   EDITOR=vim ansible-vault edit group_vars/all/vault.yml
   ```

   Le fichier est déchiffré dans un fichier temporaire, puis rechiffré à la fermeture de
   l'éditeur. Ne renommez pas la variable.

3. Appliquer :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags webserver
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags webserver
   ```

   Résultat attendu : seule la tâche `Créer le compte d'accès à la page /status` est `changed`
   (sortie masquée par `no_log: true`) ; aucun handler, car nginx relit le fichier htpasswd à
   chaque requête authentifiée.

4. Versionner le coffre rechiffré, puis transmettre le nouveau mot de passe hors Git :

   ```bash
   # (poste)
   git add ansible/group_vars/all/vault.yml
   git commit -m "chore: rotation du mot de passe /status"
   git push
   ```

**B. Changer le mot de passe Vault (`rekey`)**

1. Générer le nouveau mot de passe dans un fichier non versionné (le motif `.vault_pass*` est
   ignoré par Git) :

   ```bash
   # (poste) à défaut d'openssl : head -c 24 /dev/urandom | base64 > .vault_pass.new
   openssl rand -base64 24 > .vault_pass.new && chmod 600 .vault_pass.new
   ```

2. Rechiffrer le coffre (l'ancien mot de passe est lu dans `.vault_pass` par le script
   `fleet-vault-pass` du controller) :

   ```bash
   # (controller)
   ansible-vault rekey --new-vault-password-file ../.vault_pass.new group_vars/all/vault.yml
   ```

   Résultat attendu : `Rekey successful` (déroulé vérifié sur le banc local le 2026-11-04 :
   `ansible-vault view` puis `--tags webserver` fonctionnent ensuite avec le nouveau mot de
   passe, `changed=0`). Sous Windows (dépôt sur `C:\`), `.vault_pass.new` monté apparaît
   exécutable : le copier d'abord en `600` dans le controller
   (`install -m 600 ../.vault_pass.new /root/.vault_pass.new`) et passer
   `--new-vault-password-file /root/.vault_pass.new`.

3. Remplacer le fichier de mot de passe :

   ```bash
   # (poste)
   mv .vault_pass.new .vault_pass && chmod 600 .vault_pass
   ```

4. Versionner le coffre rechiffré, puis transmettre le nouveau mot de passe Vault à l'équipe et au
   consultant **hors Git** ; chacun remplace son `.vault_pass` après le `git pull` :

   ```bash
   # (poste)
   git add ansible/group_vars/all/vault.yml
   git commit -m "chore: changement du mot de passe Vault (rekey)"
   git push
   ```

### Vérifier que l'opération a réussi

**A. Mot de passe `/status`**

```bash
# (controller) local : node1 est joignable depuis le controller sur le réseau Docker
STATUS_PASS="$(ansible-vault view group_vars/all/vault.yml | python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["vault_webserver_status_password"])')"
curl -s -o /dev/null -w '%{http_code}\n' http://node1/status
curl -s -o /dev/null -w '%{http_code}\n' -u 'exploitation:ANCIEN_MOT_DE_PASSE' http://node1/status
curl -s -u "exploitation:${STATUS_PASS}" http://node1/status
# cloud : remplacer node1 par l'IP publique de chaque VM (203.0.113.10...)
```

Résultat attendu : `401` sans authentification, `401` avec l'ancien mot de passe, puis la page
`stub_status` avec le nouveau (les compteurs varient). Le comportement de `/status` a été observé
en local (`401` sans authentification, `401` avec un mot de passe erroné, `200` avec le bon) ; la
rotation complète, elle, est à rejouer lors de la répétition générale :

```text
Active connections: 1
server accepts handled requests
 12 12 12
Reading: 0 Writing: 1 Waiting: 0
```

Depuis le poste : `curl -u 'exploitation:<mot de passe>' http://localhost:8081/status`.

Contrôles complémentaires :

- `head -n 1 group_vars/all/vault.yml` affiche `$ANSIBLE_VAULT;1.1;AES256` (fichier toujours
  chiffré) ;
- aucune occurrence du mot de passe en clair dans le socle :

  ```bash
  # (controller)
  grep -rIlF --exclude-dir=collections --exclude-dir=.ansible -- "$STATUS_PASS" /workspace || echo "aucune occurrence en clair"
  ```

  Résultat attendu : `aucune occurrence en clair` (même contrôle observé en local : 0 occurrence
  hors `vault.yml` chiffré). Pour l'historique Git, sur le poste :
  `read -rs STATUS_PASS && git grep -F -e "$STATUS_PASS" $(git rev-list --all) || echo "absent de l'historique"` ;
- un second `ansible-playbook site.yml --tags webserver` donne `changed=0`.

**B. Mot de passe Vault**

```bash
# (controller)
ansible-vault view group_vars/all/vault.yml > /dev/null && echo "Coffre lisible avec le nouveau mot de passe"
ansible-playbook site.yml --check
```

Résultat attendu : le message de confirmation, puis `failed=0` et `changed=0`. Le contenu du coffre
est inchangé, seul son chiffrement a changé. N'affichez ce contenu
(`ansible-vault view group_vars/all/vault.yml`) qu'en l'absence de partage d'écran.

### En cas d'échec

| Symptôme | Cause | Action |
|---|---|---|
| `ERROR! Decryption failed (no vault secrets were found that could decrypt) on /workspace/ansible/group_vars/all/vault.yml` | `.vault_pass` ne correspond pas au chiffrement de `vault.yml` (rekey fait par un autre membre, fichier non remplacé) | Récupérer le mot de passe Vault courant auprès de l'équipe. Si le `mv` n'a pas encore été fait, le nouveau mot de passe est dans `.vault_pass.new`. Voir [dépannage](troubleshooting.md), erreur n° 18. |
| `Mot de passe Vault introuvable : créer socle-web-automatise/.vault_pass ...` puis `Vault password script /usr/local/bin/fleet-vault-pass returned non-zero (1)` (controller) ; `The vault password file ... was not found` (hors controller) | Fichier absent, vide ou mal nommé | Le recréer à la racine du socle : `printf '%s' '<mot de passe>' > .vault_pass && chmod 600 .vault_pass` ([dépannage](troubleshooting.md), erreur n° 6). |
| `Problem running vault password script /workspace/.vault_pass.new` pendant le `rekey` | Windows (Git Bash, dépôt sur `C:\`) : le fichier monté apparaît exécutable, Ansible l'exécute au lieu de le lire (`.vault_pass` lui-même est lu par `fleet-vault-pass`, donc protégé) | Copier `.vault_pass.new` en `600` dans `/root/` du controller et désigner cette copie (étape 2 ; [dépannage](troubleshooting.md), erreur n° 19). |
| `'vault_webserver_status_password' is undefined` | Variable renommée ou supprimée lors de l'édition | `ansible-vault edit group_vars/all/vault.yml` et restaurer le nom exact. |
| `401` avec le nouveau mot de passe | Changement non appliqué sur l'environnement testé, ou caractères mal transmis à `curl` | Relancer `--tags webserver` avec le bon `-i` ; mettre `utilisateur:motdepasse` entre guillemets ([dépannage](troubleshooting.md), erreur n° 17). |
| `403` sur `/status` | IP non autorisée par `webserver_status_allowed_networks` | Voir [RB-04](#rb-04-modifier-la-configuration-du-serveur-web). |

---

## RB-06 Vérifier la conformité d'un serveur

### Quand l'utiliser

- Avant toute intervention, pour savoir si un serveur a dérivé de ce que décrit le dépôt.
- Après une intervention manuelle suspectée sur un serveur.
- Pour prévisualiser l'effet d'une modification du dépôt avant de l'appliquer.

### Prérequis

- Controller démarré, `.vault_pass` présent, serveurs joignables.
- Le serveur a déjà été configuré une première fois par `site.yml` (voir les limites ci-dessous).

### Commandes

```bash
# (controller) local : tous les serveurs, puis un seul
ansible-playbook site.yml --check --diff
ansible-playbook site.yml --check --diff --limit node1

# (controller) cloud : tous les serveurs, une VM, ou un groupe (env_cloud, zone_us_central1_f...)
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --check --diff
ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --check --diff --limit fleetinfo-web-1

# une seule couche : --tags common | webserver | fleetinfo
ansible-playbook site.yml --check --diff --tags webserver
```

Exercice de dérive (banc local uniquement) :

```bash
# (controller) modification « manuelle » de la bannière sur node1
ansible node1 -b -m ansible.builtin.lineinfile -a "path=/etc/motd line='modification manuelle'"
ansible-playbook site.yml --check --diff --limit node1
# remise en conformité, puis nouveau contrôle
ansible-playbook site.yml --tags common --limit node1
ansible-playbook site.yml --check --diff --limit node1
```

Résultat attendu : la simulation signale `Déployer la bannière de connexion (motd)` en `changed`,
avec un diff qui retire la ligne `modification manuelle` ; après remise en conformité,
`changed=0`.

### Vérifier que l'opération a réussi

Lecture du PLAY RECAP de la simulation :

| Résultat | Interprétation | Suite |
|---|---|---|
| `changed=0`, `failed=0` | Serveur **conforme** au dépôt (observé en local sur `node1` et `node2`) | Rien à faire. |
| `changed` > 0 | **Dérive** : chaque tâche `changed` indique un écart, le diff montre la différence | Si l'écart est légitime, le reporter dans le dépôt ; sinon relancer `site.yml` (avec `--limit` ou `--tags` au besoin) pour réaligner le serveur. |
| `failed` > 0 | Simulation impossible sur ce serveur (voir ci-dessous) | Lire le message d'erreur. |
| `unreachable` > 0 | Serveur injoignable | Voir [dépannage](troubleshooting.md). |

Une simulation ne modifie rien : aucun fichier écrit, aucun handler réellement exécuté
(`Valider la configuration nginx` apparaît `skipping` s'il est notifié ; un `reload nginx` du
rôle public, notifié par un changement de `nginx.conf`, peut apparaître `changed` mais n'est que
simulé), aucune ligne dans le journal de déploiement.

### En cas d'échec

- **Serveur vierge** : `--check` échoue sur un serveur jamais configuré, car des tâches dépendent
  de paquets que la simulation n'installe pas réellement (nginx, `python3-passlib`). C'est une
  limite connue : faites d'abord un vrai `site.yml`.
- **Ce que `--check` ne vérifie pas** : le contrôle `/health` après bascule est sauté en
  simulation ; vérifiez le service avec
  `ansible web -m ansible.builtin.command -a "curl -s http://127.0.0.1/health"`.
- **Simulation d'une nouvelle version** :
  `ansible-playbook site.yml --check --diff --tags fleetinfo -e fleetinfo_version=1.4.0` annonce la
  création de la release et la bascule sans erreur (observé en local ; la bascule est forcée en
  simulation, voir [dépannage](troubleshooting.md), erreur n° 2).
- `Decryption failed` ou `.vault_pass was not found` : voir [RB-05](#rb-05-changer-le-mot-de-passe-de-status-et-le-mot-de-passe-vault).

---

## RB-07 Détruire l'environnement proprement

### Quand l'utiliser

- Fin d'une session de lab GCP (le projet est de toute façon supprimé à son expiration, mais
  détruire avant évite un state local orphelin).
- Fin de travail sur le banc local, ou remise à zéro complète du banc.

### Prérequis

- Cloud : le poste qui détient `terraform/terraform.tfstate` et le `terraform.tfvars` de la
  session, identifiants gcloud encore valides (session de lab active).
- Cloud : la clé publique `local/ssh/fleet_key.pub` doit exister, car la validation de
  `ssh_public_key_path` est évaluée aussi lors d'un `destroy`. Détruire le cloud **avant** de
  supprimer ou renouveler les clés SSH locales.
- Rien d'important à conserver sur les serveurs : ils sont reconstructibles à l'identique
  (`terraform apply` + `site.yml`) ; les journaux de déploiement disparaissent avec eux.

### Commandes

**Cloud**

```bash
# (poste) depuis socle-web-automatise/
terraform -chdir=terraform destroy
```

Résultat attendu : `Plan: 0 to add, 0 to change, 6 to destroy.` (VPC, sous-réseau, deux règles de
firewall, deux VM ; davantage si `vm_count` > 2), confirmation par `yes`, puis
`Destroy complete! Resources: 6 destroyed.` Les disques sont supprimés avec les VM
(`auto_delete = true`).

Nettoyer ensuite les fichiers propres à la session (ignorés par Git) :

```bash
# (poste)
rm -f ansible/inventories/cloud/fleet.gcp.yml
rm -rf .secrets
```

Facultatif : `gcloud auth application-default revoke` révoque les identifiants ADC du poste ;
`terraform/terraform.tfvars` peut être conservé (ignoré par Git) mais son `project_id` devra être
remplacé à la prochaine session. Dans le controller, `rm -f /root/.ssh/known_hosts` oublie les
clés d'hôte des VM détruites (leurs IP éphémères seront réattribuées).

**Local**

```bash
# (poste) depuis local/
docker compose down
```

Options :

- `docker compose down -v` : supprime aussi les volumes ; ce banc n'en déclare aucun (uniquement
  des montages et des `tmpfs`), l'option est donc sans effet supplémentaire ;
- `docker compose down --rmi all` : supprime aussi les images `fleetinfo-local/node:debian12` et
  `fleetinfo-local/controller:ansible-core-2.17` ; le prochain démarrage devra les reconstruire
  (`docker compose up -d --build --wait`, environ 1 Go à télécharger) ;
- `docker builder prune` : libère le cache de construction si l'hôte Docker manque de place ;
- dépendances Galaxy (`ansible/collections/`, `ansible/roles/geerlingguy.nginx/`) : elles restent
  sur le poste et servent au prochain démarrage. Pour les supprimer sous Linux, où elles
  appartiennent à `root` (créées dans le controller), le faire **avant** `docker compose down` :
  `docker compose exec controller rm -rf /workspace/ansible/collections /workspace/ansible/roles/geerlingguy.nginx /workspace/ansible/.ansible`.

Clés SSH (`local/ssh/`, `local/node/authorized_keys`) : conservez-les pour redémarrer le banc tel
quel. Supprimez-les uniquement pour les renouveler, puis relancez `./local/scripts/generate-keys.sh`
et `docker compose up -d --build --wait` (et `terraform -chdir=terraform apply` si des VM existent :
la métadonnée `ssh-keys` est mise à jour sur place). Conservez `.vault_pass` tant que vous
travaillez sur le projet.

### Vérifier que l'opération a réussi

Cloud (résultats attendus) :

```bash
# (poste)
gcloud compute instances list --filter="labels.app=fleetinfo"
gcloud compute networks list --filter="name=fleetinfo-vpc"
gcloud compute firewall-rules list --filter="name~^fleetinfo-vpc"
terraform -chdir=terraform state list
```

Résultat attendu : `Listed 0 items.` pour chaque commande `gcloud`, et aucune ligne pour
`terraform state list`.

Local :

```bash
# (poste) depuis local/
docker compose ps -a
docker network ls --filter name=fleetinfo-local
```

Résultat attendu : aucun conteneur `fleetinfo-local-*`, aucun réseau `fleetinfo-local_labnet`
(seule la ligne d'en-tête s'affiche).

### En cas d'échec

| Symptôme | Cause | Action |
|---|---|---|
| `terraform destroy` échoue (projet introuvable, permission refusée) après la fin du lab | Le projet a été supprimé avec la session : les ressources n'existent plus | Supprimer le state devenu obsolète : `rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup` (voir [dépannage](troubleshooting.md), erreur n° 13). |
| `Clé publique introuvable : lancer local/scripts/generate-keys.sh, ou corriger ssh_public_key_path.` | Clé publique supprimée avant le `destroy` | Restaurer la clé utilisée lors de l'`apply`, ou à défaut en générer une (`./local/scripts/generate-keys.sh`) : seule son existence est vérifiée. |
| `Error acquiring the state lock` | Une autre commande Terraform tourne | Attendre sa fin ; ne forcer le déverrouillage qu'en étant sûr qu'aucune commande n'est active. |
| Une ressource résiste (réseau encore utilisé) | Ressource créée hors Terraform dans le VPC | La supprimer dans la console ou avec `gcloud`, puis relancer `destroy`. |
| `rm` refusé sur `ansible/collections` (Linux) | Fichiers créés par `root` dans le controller | Les supprimer depuis le controller (commande ci-dessus), ou avec `sudo` sur le poste. |

---

## RB-08 Rollback automatique et simulation d'échec

### Quand l'utiliser

- Démonstration du retour arrière automatique (soutenance, formation d'un nouvel exploitant).
- Validation du mécanisme après une modification du rôle `fleetinfo`, d'abord sur le banc local.
- Jamais pour livrer une version, et jamais sur un serveur sans release précédente saine.

Le mécanisme lui-même (ADR-08) s'applique à **chaque** déploiement : `block` (génération,
bascule, contrôle `/health`), `rescue` (rebascule vers la release N-1 mémorisée avant la bascule,
rechargement de nginx, revérification, échec explicite), `always` (journal).

### Prérequis

- Tous les serveurs servent une version saine, par exemple `1.1.0`
  ([RB-01](#rb-01-déployer-une-nouvelle-version)) : c'est la version N-1 vers laquelle le
  `rescue` reviendra.
- Version simulée **différente** de la version active (par exemple `1.2.0`) : sinon un garde-fou
  refuse la simulation, faute de version vers laquelle revenir.
- Ne jamais simuler sur un serveur vierge : un premier déploiement en échec n'a pas de version
  N-1 (`resultat=ECHEC_SANS_ROLLBACK`) ; le lien `current` reste alors sur la release défectueuse
  et `/health` répond `404` jusqu'au déploiement suivant.

### Commandes

1. Provoquer l'échec : `fleetinfo_simulate_failure=true` livre la release `1.2.0` **sans**
   `health.json`, nginx répond donc `404` sur `/health`.

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true
   ```

   Déroulé sur le canari (`node1` en local ; sur le cloud, le premier hôte du groupe `web`, en
   principe `fleetinfo-web-1`), observé en local le 2026-11-03 :

   1. `Créer le répertoire de la release 1.2.0`, `Générer la page d'accueil de la release`, puis
      `Démonstration : livrer une release incomplète (sans health.json)` ;
   2. `Basculer le lien current vers la release 1.2.0` (`changed`) ;
   3. `Interroger /health jusqu'à obtenir la version 1.2.0` : cinq lignes `FAILED - RETRYING`,
      puis `fatal` avec `Status code was 404 and not [200]: HTTP Error 404: Not Found`. La première
      interrogation est suivie de 5 nouvelles tentatives (`fleetinfo_health_retries: 5`), espacées
      de 2 secondes (`fleetinfo_health_delay: 2`), soit environ 10 secondes d'attente ;
   4. `rescue` : `Mémoriser la cause de l'échec`, `Rebasculer current vers la release précédente 1.1.0`,
      `Recharger le service web`, `Vérifier que /health répond de nouveau avec la version 1.1.0`,
      `Mémoriser le succès du retour arrière`, puis `Faire échouer explicitement le déploiement`,
      dont le message (affiché sur une seule ligne) est :

      ```text
      ÉCHEC du déploiement de Fleet Info 1.2.0 sur node1. Retour arrière effectué : la version 1.1.0
      est de nouveau active et répond sur /health. Cause : Interroger /health jusqu'à obtenir la
      version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found.
      Journal : /var/log/fleetinfo/deploy.log.
      ```

   5. `always` : `Tracer la tentative de déploiement dans le journal`.

   Le canari étant en échec et `max_fail_percentage` valant 0, le play s'arrête : **les autres
   serveurs ne reçoivent jamais la version 1.2.0**. PLAY RECAP : `failed=1 rescued=1` pour le
   canari, `failed=0` pour les autres. La commande se termine avec un code retour non nul : c'est
   attendu.

2. Prouver qu'un déploiement sain fonctionne ensuite normalement :

   ```bash
   # (controller) local
   ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0
   # (controller) cloud
   ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml --tags fleetinfo -e fleetinfo_version=1.2.0
   ```

   La release `1.2.0` est régénérée complète (avec `health.json`) et déployée sur tous les
   serveurs (canari puis les autres), `failed=0` (observé en local).

3. Remettre l'environnement en cohérence avec le dépôt : soit aligner `fleetinfo_version: "1.2.0"`
   dans `vars.yml` (et committer), soit relancer `ansible-playbook site.yml --tags fleetinfo` sans
   `-e` pour revenir à la version de référence.

### Vérifier que l'opération a réussi

Après l'étape 1 (échec simulé) :

```bash
# (controller) ajouter -i inventories/cloud/fleet.gcp.yml pour le cloud
ansible web -m ansible.builtin.command -a "curl -s http://127.0.0.1/health"
ansible web -m ansible.builtin.command -a "readlink /opt/fleetinfo/current"
ansible web -b -m ansible.builtin.command -a "tail -n 1 /var/log/fleetinfo/deploy.log"
```

Résultat attendu (observé en local) :

- tous les serveurs répondent `"status": "ok"` et `"version": "1.1.0"` : le site est resté en
  ligne en version N-1 (également visible depuis le poste : `curl -s http://localhost:8081/health`) ;
- `current` pointe sur `/opt/fleetinfo/releases/1.1.0` ;
- sur le canari, la dernière ligne du journal est (ligne réelle) :

  ```text
  2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
  ```

  Les autres serveurs n'ont aucune nouvelle ligne.

Après l'étape 2 : `"version": "1.2.0"` partout et une ligne
`type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=SUCCES` sur chaque serveur.

La release cassée reste sur le disque du canari (`releases/1.2.0/` sans `health.json`) jusqu'au
déploiement sain ; `rollback.yml` refuse de basculer vers elle.

### En cas d'échec

| Symptôme | Cause | Action |
|---|---|---|
| `fleetinfo_simulate_failure=true exige une version DIFFÉRENTE de la version active (...)` | Version simulée égale à la version active | Choisir une autre version (`-e fleetinfo_version=1.2.0` si `1.1.0` est active). Rien n'a été modifié. |
| `resultat=ECHEC_SANS_ROLLBACK`, message `Aucune version précédente vers laquelle revenir (premier déploiement ou mise à jour sur place de la release active) : le lien current reste sur la release demandée.` | Simulation sur un serveur sans release précédente | Déployer immédiatement une version saine : `ansible-playbook site.yml` (avec le bon `-i`). |
| `resultat=ECHEC_ROLLBACK_KO`, message `Retour arrière vers la version X effectué mais NON confirmé : /health ne répond pas avec cette version. INTERVENTION MANUELLE requise (docs/troubleshooting.md).` | La version N-1 ne répond pas non plus (reproduit le 2026-11-04 en supprimant le `health.json` de N-1) | Incident : [dépannage, erreur n° 23](troubleshooting.md#23-retour-arrière-non-confirmé-echec_rollback_ko) ; vérifier nginx (`sudo systemctl status nginx`, `sudo nginx -t`), puis régénérer une release saine avec `site.yml` (RB-02 méthode (a)) ou rebasculer vers une release complète avec `ansible-playbook rollback.yml -e fleetinfo_rollback_version=X.Y.Z` ([RB-02](#rb-02-revenir-à-une-version-précédente)). |
| Le déploiement sain de l'étape 2 échoue | Problème réel, indépendant de la simulation | Lire la cause (`detail=` du journal), voir [dépannage](troubleshooting.md). |
