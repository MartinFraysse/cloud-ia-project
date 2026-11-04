# Rôle `webserver`

Site nginx de Fleet Info et page `/status` protégée, au-dessus de l'installation de nginx
fournie par le rôle public `geerlingguy.nginx`.

Documents liés : [référence des variables](../../../docs/variables.md#52-rôle-webserver) ·
[décisions techniques](../../../docs/decisions.md) (ADR-04, ADR-10, ADR-11) ·
[runbooks](../../../docs/runbooks.md) · [dépannage](../../../docs/troubleshooting.md).

## Objectif

- Installer et configurer nginx (délégué à `geerlingguy.nginx`, exécuté en dépendance).
- Publier le site Fleet Info sur le port `webserver_listen_port` :
  - `/` : page d'accueil de la release active (`/opt/fleetinfo/current/index.html`) ;
  - `/health` : contrôle de santé JSON (`health.json` de la release active) ;
  - `/status` : page technique `stub_status` de nginx, protégée par authentification HTTP Basic
    (mot de passe géré par Ansible Vault), éventuellement restreinte à des plages IP.
- Valider toute nouvelle configuration (`nginx -t`) **avant** de recharger nginx.

Le contenu servi (releases, lien `current`) appartient au rôle `fleetinfo`.

## Fonctionnement (tâches dans l'ordre)

| # | Tâche | Module | Ce qu'elle fait |
|---|---|---|---|
| 0 | Dépendance `geerlingguy.nginx` (automatique, avant **tout** le reste du rôle) | `meta/main.yml` | Installe le paquet `nginx`, supprime le site `default` de Debian, pose `/etc/nginx/nginx.conf` (via notre enveloppe `templates/nginx.conf.j2`, qui ajoute l'en-tête `ansible_managed`) validé par `nginx -t -c %s`, démarre et active le service. Détail plus bas. |
| 1 | Validation des arguments (automatique, tâche « Validating arguments against arg spec 'main' », taguée `always`) | `meta/argument_specs.yml` | Vérifie les types ; `webserver_status_password` est **obligatoire** (`required: true`, `no_log: true`). Elle s'exécute **après** la dépendance : sans mot de passe, nginx est donc déjà installé quand le play s'arrête. |
| 2 | Installer passlib (bibliothèque requise par le module htpasswd) | `ansible.builtin.apt` | Paquet `python3-passlib` sur la cible. |
| 3 | Créer le compte d'accès à la page /status | `community.general.htpasswd` | Écrit le compte `webserver_status_user` haché en `webserver_status_crypt_scheme` dans `/etc/nginx/fleetinfo-status.htpasswd` (root:www-data, 0640). `no_log: true`. Aucun handler : nginx relit ce fichier à chaque requête authentifiée. |
| 4 | Déployer la configuration du site Fleet Info | `ansible.builtin.template` | Génère `/etc/nginx/sites-enabled/fleetinfo.conf` depuis `templates/fleetinfo.conf.j2` (root:root, 0644). **Avant écriture**, `validate:` teste le fichier candidat avec `nginx -t -q` dans une configuration minimale (`events {} http { include /etc/nginx/mime.types; include <candidat>; }`) : invalide, la tâche échoue et le fichier en place est conservé. Notifie « Valider la configuration nginx » **seulement si le fichier a changé**. |
| 5 | Fin du play : handlers | `handlers/main.yml` | « Valider la configuration nginx » puis « Recharger nginx » (section Handlers). |

Configuration produite par le template (extrait commenté) :

- `listen <port> default_server;` sans `listen [::]` : les conteneurs du banc local n'ont pas
  d'IPv6 et nginx refuserait de démarrer ; les VM GCP du socle n'en ont pas non plus ;
- `root /opt/fleetinfo/current;` : nginx résout le lien à **chaque requête**, la bascule de
  release est donc instantanée et ne demande aucun rechargement ;
- `location = /health` : `try_files /health.json =404`, type `application/json` ; une release
  incomplète (sans `health.json`) répond 404, ce qui fait échouer le déploiement ;
- `location = /status` : `stub_status`, `allow` par plage de `webserver_status_allowed_networks`
  puis `deny all` (seulement si la liste n'est pas vide), `auth_basic`, `access_log off` ;
- en-têtes `X-Content-Type-Options: nosniff` et `X-Frame-Options: DENY`.

## Variables

Valeurs par défaut : [`defaults/main.yml`](defaults/main.yml) (précédence la plus faible).
Toutes sont préfixées `webserver_`.

| Variable | Défaut | Description |
|---|---|---|
| `webserver_listen_port` | `80` | Port d'écoute HTTP du site. Le socle le fixe une seule fois via `socle_http_port` (`group_vars/all/vars.yml`), partagé avec le contrôle de santé du rôle `fleetinfo`. |
| `webserver_document_root` | `/opt/fleetinfo/current` | Racine servie : le lien symbolique `current` géré par le rôle `fleetinfo`. |
| `webserver_status_user` | `"exploitation"` | Compte autorisé sur la page `/status` (authentification HTTP Basic). |
| `webserver_status_password` | aucun (obligatoire) | Mot de passe de ce compte. Secret : aucune valeur par défaut ; le socle le fournit via `group_vars/all/vars.yml` → `vault_webserver_status_password` (Vault). |
| `webserver_status_crypt_scheme` | `apr_md5_crypt` | Algorithme de hachage du fichier htpasswd. Valeurs acceptées : `apr_md5_crypt`, `sha256_crypt`, `sha512_crypt`, `md5_crypt`. |
| `webserver_status_allowed_networks` | `[]` | Plages IP autorisées sur `/status` **en plus** de l'authentification (vide = toutes). Exemple : `["10.10.0.0/24"]`. |

Surcharges appliquées par le socle (`group_vars/all/vars.yml`) :

| Variable | Valeur | Valeur effective |
|---|---|---|
| `webserver_listen_port` | `"{{ socle_http_port }}"` | `80` |
| `webserver_document_root` | `"{{ socle_app_root }}/current"` | `/opt/fleetinfo/current` |
| `webserver_status_password` | `"{{ vault_webserver_status_password }}"` | valeur chiffrée dans `group_vars/all/vault.yml` |

Pourquoi `apr_md5_crypt` : c'est un format que nginx vérifie lui-même, sans coût CPU notable par
requête ; la robustesse repose sur un mot de passe long et aléatoire (24 caractères, stocké dans
Vault). Alternative documentée : `sha512_crypt` ([ADR-11](../../../docs/decisions.md)).

## Constantes internes

[`vars/main.yml`](vars/main.yml) : chemins Debian, non destinés à être surchargés.

| Variable | Valeur | Description |
|---|---|---|
| `webserver_site_path` | `/etc/nginx/sites-enabled/fleetinfo.conf` | Fichier du site, inclus par le `nginx.conf` de `geerlingguy.nginx` (`include /etc/nginx/sites-enabled/*;`). |
| `webserver_status_htpasswd_path` | `/etc/nginx/fleetinfo-status.htpasswd` | Comptes autorisés sur `/status` (format htpasswd). |
| `webserver_nginx_group` | `www-data` | Groupe des workers nginx sous Debian : il doit pouvoir lire le fichier htpasswd. |
| `webserver_access_log` | `/var/log/nginx/fleetinfo.access.log` | Journal d'accès du site. |
| `webserver_error_log` | `/var/log/nginx/fleetinfo.error.log` | Journal d'erreurs du site. |

## Handlers

[`handlers/main.yml`](handlers/main.yml) : deux handlers **chaînés** par `notify`.

```
 template fleetinfo.conf ──(changed)──▶ « Valider la configuration nginx » ──(succès)──▶ « Recharger nginx »
                                          ansible.builtin.command: nginx -t      ansible.builtin.service: reloaded
                                                     │
                                                  (échec) ─▶ la chaîne s'arrête : pas de rechargement,
                                                             nginx garde la configuration chargée en mémoire
```

| Handler | Module | Détail |
|---|---|---|
| Valider la configuration nginx | `ansible.builtin.command: nginx -t` | `command` est nécessaire : aucun module ne valide une configuration nginx. `changed_when: true` est volontaire : c'est ce qui permet de notifier le handler suivant ; sans risque pour l'idempotence puisque ce handler ne s'exécute que si la configuration a changé. |
| Recharger nginx | `ansible.builtin.service` (`state: reloaded`) | Exécuté uniquement si la validation a réussi. |

**Reload plutôt que restart.** Un reload (SIGHUP) relit la configuration sans couper les
connexions en cours ni interrompre le service, et suffit pour tout ce que gère ce rôle (site,
port d'écoute, `/status`). Le seul redémarrage du socle est celui déclenché par
`geerlingguy.nginx` au **premier passage**, quand il supprime le site `default` de Debian
([ADR-10](../../../docs/decisions.md)).

Les handlers s'exécutent à la fin du play « Configurer le serveur web nginx », donc **avant** le
play de déploiement applicatif : `fleetinfo` vérifie `/health` sur une configuration déjà
rechargée.

Comportements vérifiés sur le banc local :

| Changement | Handlers exécutés | Résultat |
|---|---|---|
| Variable n'affectant que la page (ex. `-e fleetinfo_environment=demo`) | aucun | Page régénérée par `fleetinfo`, nginx non rechargé |
| Configuration du site (ex. `webserver_status_allowed_networks`) | Valider, puis Recharger | Nouvelle configuration active |
| Configuration invalide (ex. `-e webserver_listen_port=99999`) | aucun | Refusée **avant écriture** par `validate:` (`[emerg] invalid port in "99999" of the "listen" directive`) : fichier en place inchangé, site toujours en ligne (2026-11-04) |
| Changement de port (`-e socle_http_port=8080`), puis retour à 80 | Valider, puis Recharger (à chaque fois) | nginx écoute sur le nouveau port ; le contrôle `/health` de `fleetinfo` suit (`fleetinfo_health_port`) ; puis `changed=0` (2026-11-04) |
| Deuxième passage sans changement | aucun | `changed=0` |

Deux garde-fous successifs : `validate:` empêche d'**écrire** un fichier de site invalide ; la
chaîne de handlers revalide la configuration **complète** (`nginx -t`) avant tout rechargement.
Une configuration invalide n'est donc jamais appliquée, ni écrite sur disque. Rejoué seul,
le rôle est idempotent : `--tags webserver` au second passage donne `changed=0` (ok=17,
2026-11-04).

## Fichiers générés sur le serveur

| Fichier | Produit par | En-tête |
|---|---|---|
| `/etc/nginx/sites-enabled/fleetinfo.conf` | `templates/fleetinfo.conf.j2` (ce rôle) | `# Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : ...` puis `# Source : roles/webserver/templates/fleetinfo.conf.j2` |
| `/etc/nginx/fleetinfo-status.htpasswd` | module `community.general.htpasswd` (ce rôle) | aucun (fichier de données géré par le module, pas par un template) ; root:www-data, 0640 |
| `/etc/nginx/nginx.conf` | `templates/nginx.conf.j2` (ce rôle) : enveloppe qui inclut tel quel le template `nginx.conf.j2` de `geerlingguy.nginx` | `# Géré par Ansible ...` puis deux lignes `# Source : ...` (enveloppe et template du rôle public) |
| `/etc/nginx/sites-enabled/default` | supprimé par `geerlingguy.nginx` | — |
| `/var/log/nginx/fleetinfo.access.log`, `/var/log/nginx/fleetinfo.error.log` | nginx | journaux du site, créés par nginx en root:root 0644 (constaté sur le banc local) : lisibles par le compte `fleetops` |

Vérification (depuis `socle-web-automatise/local/` sur le poste) :

```bash
docker compose exec node1 head -n 2 /etc/nginx/sites-enabled/fleetinfo.conf
docker compose exec node1 nginx -t
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/status
curl -s -o /dev/null -w '%{http_code}\n' -u exploitation:<mot_de_passe> http://localhost:8081/status
```

Résultat attendu : les deux lignes d'en-tête ; `syntax is ok` et `test is successful` ; `401`
sans authentification (et avec un mauvais mot de passe) ; `200` avec le bon mot de passe (lu par
`ansible-vault view group_vars/all/vault.yml` dans le controller). Vérifié sur le banc local.

## Dépendances

| Type | Dépendance | Version | Usage |
|---|---|---|---|
| Rôle (Galaxy) | `geerlingguy.nginx` | 3.3.1 (`requirements.yml`) | Paquet, `nginx.conf`, service (dépendance déclarée dans `meta/main.yml`) |
| Collection | `community.general` | 12.6.7 (`requirements.yml`) | Module `community.general.htpasswd` |
| Paquet cible | `python3-passlib` | paquet Debian (1.7.4 constaté) | Requis par le module htpasswd ; installé par le rôle |
| Moteur | ansible-core | 2.17 | — |
| Système cible | Debian 12 (bookworm), systemd | — | Service nginx géré par systemd |
| Données | `webserver_status_password` | — | Fourni par Ansible Vault |

Le rôle ne dépend pas de `fleetinfo` : il sert un répertoire qui peut ne pas encore exister au
premier passage (`nginx -t` ne vérifie pas l'existence de `root`). `fleetinfo` le remplit ensuite.

Installation des dépendances, dans le controller (`/workspace/ansible`) :

```bash
ansible-galaxy install -r requirements.yml
```

Résultat attendu : `geerlingguy.nginx (3.3.1) was installed successfully` (rôle dans
`ansible/roles/geerlingguy.nginx/`, collections dans `ansible/collections/`, tous ignorés par Git).

## Rôle public `geerlingguy.nginx`

Justification complète du choix : [ADR-04](../../../docs/decisions.md).

### Ce qu'il fait pour nous

Exécuté automatiquement avant les tâches de `webserver` (dépendance `meta/main.yml`), avec les
tâches suivantes sur Debian (ordre confirmé par `ansible-playbook site.yml --list-tasks` sur le
banc local) : `Include OS-specific variables.` (charge `vars/Debian.yml`),
`Define nginx_user.`, `Update apt cache.`, `Ensure nginx is installed.`,
`Remove default nginx vhost config file (if configured).`, `Ensure nginx_vhost_path exists.`,
`Add managed vhost config files.` et `Remove managed vhost config files.` (boucles sur
`nginx_vhosts`, vide : rien à faire), `Remove legacy vhosts.conf file.`,
`Copy nginx configuration in place.` (avec `validate: nginx -t -c %s`),
`Ensure nginx service is running as configured.`

### Pourquoi ce rôle plutôt qu'un rôle maison

- **Le besoin est standard** : installer nginx, poser un `nginx.conf` correct, gérer le service.
  C'est exactement le périmètre du rôle, éprouvé sur de nombreuses distributions.
- **`nginx.conf` validé avant d'être posé** (`validate: nginx -t -c %s`) : un `nginx.conf`
  invalide n'arrive jamais sur disque.
- **Découpage clair des responsabilités** : le rôle public gère le serveur, notre rôle
  `webserver` gère ce qui est propre au socle (site, `/health`, `/status`, chaîne de validation).
  Le code maison reste court et lisible.
- **Rôles publics autorisés** par les consignes pour l'infrastructure (`common`, `nginx`), et
  interdits pour `fleetinfo`, écrit par l'équipe.

### État de maintenance (relevé le 2026-11-03)

| Critère | Constat |
|---|---|
| Dépôt source | `geerlingguy/ansible-role-nginx` sur GitHub, **non archivé** |
| Dernière publication | **3.3.1, le 2026-08-10** (version épinglée dans `requirements.yml`) ; précédentes : 3.3.0 (2025-12-02), 3.2.0 (2024-03-23) |
| Popularité | environ **16 millions** de téléchargements sur Ansible Galaxy (15 824 801 relevés) |
| Licence | **MIT** (fichier `LICENSE` ; le champ `license` de son `meta/main.yml` indique « license (BSD, MIT) ») |
| Auteur | Jeff Geerling, mainteneur de nombreux rôles Galaxy de référence |

### Compatibilité avec Debian 12

- `meta/main.yml` du rôle public : plateforme `Debian`, versions `all`.
- `vars/Debian.yml` fournit les chemins Debian : `nginx_conf_file_path: /etc/nginx/nginx.conf`,
  `nginx_vhost_path: /etc/nginx/sites-enabled`,
  `nginx_default_vhost_path: /etc/nginx/sites-enabled/default`, utilisateur `www-data`.
- Le `nginx.conf` généré inclut `/etc/nginx/conf.d/*.conf` et `/etc/nginx/sites-enabled/*` :
  notre `fleetinfo.conf` y est donc chargé sans configuration supplémentaire.
- Installe le paquet `nginx` de Debian (nginx 1.22.1 sur Debian 12, constaté sur le banc local).
- Vérifié sur le banc local (Debian 12 bookworm, systemd) : premier passage, idempotence
  (`changed=0`), `--check --diff`.

### Variables surchargées et pourquoi

Mot-clé `vars` de la dépendance dans [`meta/main.yml`](meta/main.yml) (précédence de niveau
« vars de rôle » : l'emporte sur les defaults du rôle public et sur les `group_vars`).

| Variable | Défaut du rôle public | Valeur du socle | Pourquoi |
|---|---|---|---|
| `nginx_remove_default_vhost` | `false` | `true` | Le site `default` de Debian écoute aussi sur 80 en `default_server` : conflit avec notre site (`nginx -t` : « duplicate default server »). |
| `nginx_vhosts` | `[]` | `[]` | Posé explicitement : le mécanisme de vhosts du rôle public n'est pas utilisé ; notre site est un template de **ce** rôle, avec sa propre chaîne de handlers (validation puis rechargement). |
| `nginx_server_tokens` | `"on"` | `"off"` | Masque la version de nginx dans les en-têtes HTTP et les pages d'erreur. |
| `nginx_conf_template` | `"nginx.conf.j2"` | `"{{ playbook_dir }}/roles/webserver/templates/nginx.conf.j2"` | Enveloppe qui ajoute l'en-tête `ansible_managed` puis fait `{% include 'roles/geerlingguy.nginx/templates/nginx.conf.j2' %}` (mécanisme de surcharge prévu par le rôle public, chemin relatif au dossier `ansible/`) : contenu de `nginx.conf` inchangé, fichier identifiable comme géré par Ansible. |

Les autres variables du rôle public restent à leur défaut (`nginx_service_state: started`,
`nginx_service_enabled: true`, `nginx_worker_processes` = nombre de vCPU...). Liste dans la
[référence des variables](../../../docs/variables.md#8-variables-de-geerlingguynginx-surchargées).

### Risques identifiés et parades

| Risque | Conséquence | Parade |
|---|---|---|
| Modules en nom court (non-FQCN) : `include_vars`, `set_fact`, `template`, `service`, `apt`, `file`, `command` | Non conforme au profil `production` d'`ansible-lint` | Rôle exclu d'`ansible-lint` (`exclude_paths: roles/geerlingguy.nginx/` dans `.ansible-lint`) ; notre code reste lint propre |
| **Restart** au premier passage | La suppression du site `default` notifie `restart nginx` : coupure brève, une seule fois, sur un serveur pas encore en service | Accepté : n'arrive qu'à l'installation ; ensuite le fichier n'existe plus et la tâche est `ok` |
| Reload conditionné à `nginx_service_state` | Le handler `reload nginx` du rôle public a `when: nginx_service_state == "started"` : si quelqu'un passe cette variable à `stopped`, un changement de `nginx.conf` ne serait pas rechargé | Ne pas surcharger `nginx_service_state` ; notre handler « Recharger nginx » n'a pas cette condition |
| Template `nginx.conf.j2` du rôle public sans en-tête `ansible_managed` | Un administrateur ne serait pas averti que `/etc/nginx/nginx.conf` est géré par Ansible | **Corrigé** : enveloppe `templates/nginx.conf.j2` (variable `nginx_conf_template`). À la montée de version du rôle public, vérifier que le chemin `templates/nginx.conf.j2` existe toujours |
| Dépendance à un tiers | Une future version peut changer de comportement ou ne plus être maintenue | Version **épinglée** (3.3.1) ; montée de version : lire le changelog, modifier `requirements.yml`, `ansible-galaxy install -r requirements.yml --force`, rejouer `site.yml` deux fois sur le banc local (`changed=0`), puis `--check --diff` sur le cloud |
| Cache apt du rôle public (`cache_valid_time=86400`, `changed_when: false`) | Rafraîchissement du cache au plus une fois par jour, jamais signalé comme changement | Sans impact : `common` a déjà rafraîchi le cache au premier passage |

## Exemple d'utilisation

Extrait de `site.yml` (deuxième play) :

```yaml
- name: Configurer le serveur web nginx
  hosts: web
  become: true
  roles:
    - role: webserver
      tags: [webserver]
```

Usage autonome, avec `/status` réservé au sous-réseau interne :

```yaml
- name: Serveur web Fleet Info
  hosts: web
  become: true
  roles:
    - role: webserver
      vars:
        webserver_status_password: "{{ vault_webserver_status_password }}"
        webserver_status_allowed_networks:
          - "10.10.0.0/24"
```

Rejouer uniquement ce rôle (par exemple après un changement du mot de passe de `/status`) :

```bash
ansible-playbook site.yml --tags webserver
```

## Idempotence

- Le module `htpasswd` vérifie le mot de passe existant avant d'écrire : même mot de passe, pas
  de changement.
- Le template du site ne contient que des valeurs stables ; `ansible_managed` n'a ni date ni
  chemin.
- Les handlers ne s'exécutent que si le template a changé ; « Valider la configuration nginx »
  est `changed` par construction, mais n'est jamais appelé sur un serveur conforme.
- `python3-passlib` en `state: present`.

Vérifié sur le banc local : deuxième passage de `site.yml` sans aucun handler exécuté,
`changed=0`.

## Licence et auteur

Licence MIT. Auteur : Équipe Plateforme NovaRetail (`namespace: novaretail`, `meta/main.yml`).
Le rôle public `geerlingguy.nginx` est sous licence MIT, auteur Jeff Geerling.
