# Rôle `common`

Socle système appliqué à **tout** serveur du socle web, avant nginx et l'application.

Documents liés : [référence des variables](../../../docs/variables.md#51-rôle-common) ·
[décisions techniques](../../../docs/decisions.md) · [runbooks](../../../docs/runbooks.md) ·
[dépannage](../../../docs/troubleshooting.md).

## Objectif

Rendre chaque serveur conforme à une base commune, identique en local et sur le cloud :

- cible vérifiée (Debian 12 sous systemd) avant toute modification ;
- paquets de base installés ;
- fuseau horaire réglé ;
- compte d'exploitation `fleetops` créé, **sans sudo** (lecture des journaux uniquement) ;
- bannière de connexion `/etc/motd` qui indique l'hôte, l'environnement et où regarder.

## Fonctionnement (tâches dans l'ordre)

Fichier unique : [`tasks/main.yml`](tasks/main.yml). L'élévation de privilèges (`become: true`)
est déclarée par le play dans `site.yml`, pas dans le rôle.

| # | Tâche | Module | Ce qu'elle fait |
|---|---|---|---|
| 0 | Validation des arguments (automatique) | `meta/argument_specs.yml` | Ansible vérifie les types des variables d'entrée avant la première tâche ; une valeur invalide arrête le play avec un message explicite. |
| 1 | Vérifier que la cible est une Debian 12 gérée par systemd | `ansible.builtin.assert` | Échoue tôt si `distribution != Debian`, `distribution_major_version != 12` ou `service_mgr != systemd`. |
| 2 | Installer les paquets de base | `ansible.builtin.apt` | Installe `common_packages` ; met à jour le cache apt seulement s'il a plus de `common_apt_cache_valid_time` secondes. |
| 3 | Régler le fuseau horaire | `community.general.timezone` | Applique `common_timezone` via `timedatectl` (systemd-timedated, D-Bus). |
| 4 | Créer l'utilisateur d'exploitation | `ansible.builtin.user` | Crée `common_ops_user` (shell bash, répertoire personnel) et **ajoute** les groupes `common_ops_user_groups` (`append: true`) sans retirer les autres. |
| 5 | Déployer la bannière de connexion (motd) | `ansible.builtin.template` | Génère `/etc/motd` depuis `templates/motd.j2` (root:root, 0644). |

## Variables

Valeurs par défaut : [`defaults/main.yml`](defaults/main.yml) (précédence la plus faible,
surchargeables partout). Toutes sont préfixées `common_`.

| Variable | Défaut | Description |
|---|---|---|
| `common_packages` | `[curl, vim, ca-certificates, tzdata]` | Paquets de base présents sur tout serveur du socle. |
| `common_apt_cache_valid_time` | `3600` | Durée (secondes) pendant laquelle le cache apt est considéré comme frais : évite un `apt-get update` à chaque exécution. |
| `common_timezone` | `"Europe/Paris"` | Fuseau horaire du serveur (format IANA). |
| `common_ops_user` | `"fleetops"` | Utilisateur d'exploitation : lecture des journaux, sans sudo (moindre privilège). |
| `common_ops_user_groups` | `[adm, systemd-journal]` | Groupes secondaires : `adm` pour lire `/var/log/*` (journaux nginx et de déploiement), `systemd-journal` pour `journalctl`. |
| `common_environment` | `"{{ socle_env \| default('inconnu') }}"` | Environnement affiché dans la bannière ; `socle_env` vient des `group_vars` d'inventaire (`local` ou `cloud`). |
| `common_motd_extra_lines` | `[]` | Lignes libres ajoutées à la bannière. |
| `common_motd_footer` | `"Serveur géré par Ansible : aucune modification manuelle, passer par le dépôt Git."` | Dernière ligne de la bannière. |

Surcharges appliquées par le socle :

| Variable | Valeur effective | Où |
|---|---|---|
| `common_environment` | `local` / `cloud` (via `socle_env`) | `inventories/local/group_vars/all.yml`, `inventories/cloud/group_vars/all.yml` |
| `common_motd_extra_lines` | 3 lignes : release active (`/opt/fleetinfo/current`), journal (`/var/log/fleetinfo/deploy.log`), site nginx (`/etc/nginx/sites-enabled/fleetinfo.conf`) | `group_vars/all/vars.yml` |

## Constantes internes

[`vars/main.yml`](vars/main.yml) (précédence forte : non destinées à être surchargées).

| Variable | Valeur | Description |
|---|---|---|
| `common_motd_path` | `/etc/motd` | Bannière affichée après chaque connexion SSH (pam_motd, Debian). |

## Handlers

**Aucun**, volontairement ([`handlers/main.yml`](handlers/main.yml) contient une liste vide pour
respecter l'arborescence standard) :

- le fuseau horaire est appliqué immédiatement par `timedatectl` ; aucun service à redémarrer ;
- `/etc/motd` est relu par pam_motd à chaque nouvelle connexion SSH ;
- les paquets installés par défaut (`curl`, `vim`, `ca-certificates`, `tzdata`) ne fournissent
  aucun service.

## Fichiers générés sur le serveur

| Fichier | Source | En-tête |
|---|---|---|
| `/etc/motd` | `templates/motd.j2` | `# Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : ...` puis `# Source : roles/common/templates/motd.j2` |

Le compte `fleetops` (et `/home/fleetops`) est créé par le module `user`, pas par un template.

Contenu constaté sur le nœud local `node1` :

```
# Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement
# Source : roles/common/templates/motd.j2
==========================================================================
  Socle Web Automatisé - NovaRetail
  Hôte          : node1
  Environnement : local
  Système       : Debian 12.15 (bookworm)
  Compte d'exploitation : fleetops (lecture des journaux, sans sudo)
  Application   : Fleet Info (release active : /opt/fleetinfo/current)
  Journal       : /var/log/fleetinfo/deploy.log
  Site nginx    : /etc/nginx/sites-enabled/fleetinfo.conf
  Serveur géré par Ansible : aucune modification manuelle, passer par le dépôt Git.
==========================================================================
```

Vérification (depuis `socle-web-automatise/local/` sur le poste) :

```bash
docker compose exec node1 head -n 2 /etc/motd
docker compose exec node1 id fleetops
docker compose exec node1 timedatectl show -p Timezone
```

Résultat attendu : les deux lignes d'en-tête ci-dessus ;
`uid=1001(fleetops) gid=1001(fleetops) groups=1001(fleetops),4(adm),999(systemd-journal)`
(identifiants numériques constatés en local, ils peuvent différer sur une VM) ;
`Timezone=Europe/Paris`.

Côté cloud, depuis `socle-web-automatise/` sur le poste (et non depuis `local/`) :
`ssh -i local/ssh/fleet_key ansible@<IP>` (IP donnée par
`terraform -chdir=terraform output vm_public_ips`). Résultat attendu, à confirmer lors de la
répétition générale : la même bannière à la connexion, avec `Environnement : cloud`.

## Dépendances

| Type | Dépendance | Version | Usage |
|---|---|---|---|
| Collection | `community.general` | 12.6.7 (`requirements.yml`) | Module `community.general.timezone` |
| Moteur | ansible-core | 2.17 (`min_ansible_version: "2.17"`) | — |
| Rôle | aucun | — | `dependencies: []` dans `meta/main.yml` |
| Système cible | Debian 12 (bookworm), systemd en PID 1, D-Bus, Python 3, sudo | — | `timedatectl` exige systemd-timedated et D-Bus : c'est pourquoi l'image des nœuds locaux embarque `systemd`, `systemd-sysv` et `dbus` ([ADR-03](../../../docs/decisions.md)) |

## Exemple d'utilisation

Extrait de `site.yml` (premier play) :

```yaml
- name: Appliquer le socle système commun
  hosts: web
  become: true
  roles:
    - role: common
      tags: [common]
```

Usage autonome avec une surcharge :

```yaml
- name: Socle système avec un autre fuseau horaire
  hosts: web
  become: true
  roles:
    - role: common
      vars:
        common_timezone: "UTC"
        common_motd_extra_lines:
          - "Contact       : equipe-plateforme"
```

Rejouer uniquement ce rôle, dans le controller (`/workspace/ansible`) :

```bash
ansible-playbook site.yml --tags common
```

## Idempotence

- `apt` en `state: present` : aucun changement si les paquets sont déjà installés ;
  `cache_valid_time` évite de rafraîchir le cache à chaque passage.
- `timezone` et `user` comparent l'état courant à l'état demandé ; `append: true` n'ajoute que
  les groupes manquants.
- La bannière ne contient que des valeurs stables (aucune date, aucun uptime) et
  `ansible_managed` ne contient ni date ni chemin absolu.

Vérifié sur le banc local : `ansible-playbook site.yml --tags common` rejoué seul donne
`changed=0` sur `node1` et `node2`.

## Licence et auteur

Licence MIT. Auteur : Équipe Plateforme NovaRetail (`namespace: novaretail`, `meta/main.yml`).
