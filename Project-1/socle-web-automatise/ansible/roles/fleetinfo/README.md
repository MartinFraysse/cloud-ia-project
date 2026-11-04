# Rôle `fleetinfo`

Déploiement versionné de l'application **Fleet Info** : releases, bascule atomique, contrôle de
santé, retour arrière automatique et manuel, journal des déploiements. Rôle écrit par l'équipe
(les rôles publics sont interdits pour l'application).

Documents liés : [référence des variables](../../../docs/variables.md#53-rôle-fleetinfo) ·
[décisions techniques](../../../docs/decisions.md) (ADR-08, ADR-13) ·
[runbooks](../../../docs/runbooks.md) · [dépannage](../../../docs/troubleshooting.md).

## Objectif

- Générer, **à partir des facts de chaque serveur**, une page d'accueil et une réponse `/health`
  propres à la machine, dans un répertoire de release versionné
  `/opt/fleetinfo/releases/<version>/`.
- Rendre la release active en basculant **atomiquement** le lien `/opt/fleetinfo/current`.
- Vérifier après la bascule que `/health` répond `status: ok` avec la version attendue.
- En cas d'échec, revenir **automatiquement** à la release précédente, vérifier qu'elle répond,
  puis faire échouer le play avec un message clair.
- Tracer chaque tentative dans `/var/log/fleetinfo/deploy.log`.
- Permettre un retour arrière **manuel** vers une release déjà présente (`rollback.yml`).
- Ne conserver que les `fleetinfo_keep_releases` releases les plus récentes.

## Points d'entrée

Le rôle a deux points d'entrée, chacun validé par `meta/argument_specs.yml` :

| Point d'entrée | Appelé par | Fichier | Rôle |
|---|---|---|---|
| `main` | `site.yml` (troisième play, tag `fleetinfo`) | [`tasks/main.yml`](tasks/main.yml) | Déploie `fleetinfo_version` |
| `rollback` | `rollback.yml` (`include_role` avec `tasks_from: rollback`) | [`tasks/rollback.yml`](tasks/rollback.yml) | Rebascule vers une release déjà présente, sans la régénérer |

Les deux réutilisent [`tasks/prepare.yml`](tasks/prepare.yml) (arborescence) et
[`tasks/deploy.yml`](tasks/deploy.yml) (cycle block/rescue/always).

## Fonctionnement du point d'entrée `main` (tâches dans l'ordre)

| # | Tâche | Fichier | Ce qu'elle fait |
|---|---|---|---|
| 0 | Validation des arguments (automatique) | `meta/argument_specs.yml` | Types des variables d'entrée vérifiés avant la première tâche. |
| 1 | Vérifier le format de la version demandée | `main.yml` | `fleetinfo_version` doit respecter `^[0-9]+\.[0-9]+\.[0-9]+$`. |
| 2 | Créer les répertoires de l'application | `prepare.yml` | `/opt/fleetinfo`, `/opt/fleetinfo/releases`, `/etc/ansible/facts.d` (root:root, 0755). |
| 3 | Créer le répertoire du journal de déploiement | `prepare.yml` | `/var/log/fleetinfo` (root:adm, 0750). |
| 4 | Lire la release actuellement active | `deploy.yml` | `stat` du lien `current`. |
| 5 | Mémoriser la release active avant bascule (cible d'un éventuel retour arrière) | `deploy.yml` | `fleetinfo_active_dir` = cible du lien (vide au premier déploiement) ; statut `EN_COURS`. |
| 6 | Calculer le contexte du déploiement | `deploy.yml` | `fleetinfo_active_version` (N-1) ; `fleetinfo_deploy_needed` = le lien doit-il changer de release ? |
| 7 | Dater le déploiement et identifier la release précédente | `deploy.yml` | Si bascule : date de l'exécution et version active comme précédente. Sinon : valeurs relues dans le fait local (idempotence). |
| 8 | Refuser une simulation d'échec sur la version déjà active | `deploy.yml` | Garde-fou : `fleetinfo_simulate_failure=true` exige une version différente de la version active. |
| 9 | **block** « Déployer avec retour arrière automatique la version X.Y.Z » | `deploy.yml` | Voir le cycle ci-dessous. |
| 10 | Lister les releases présentes sur le serveur | `cleanup.yml` | `find` des répertoires de `releases/`. |
| 11 | Supprimer les releases les plus anciennes au-delà de la limite de N | `cleanup.yml` | Ménage (voir plus bas). |

Si le déploiement échoue, le rescue se termine par un échec explicite : l'hôte est en échec et le
ménage (tâches 10 et 11) n'est pas exécuté pour lui.

## Cycle block / rescue / always

```
 AVANT LE BLOCK   stat /opt/fleetinfo/current ──▶ N-1 mémorisée (fleetinfo_active_dir)
                  date et version précédente calculées ; garde-fous : version imposée par -e
                  pendant un rollback manuel, simulation d'échec sur la version active
                                         │
 BLOCK                                   ▼
   1. Créer le répertoire de la release X.Y.Z                    releases/X.Y.Z/
   2. Générer la page d'accueil de la release                    index.html
   3. Générer la réponse du contrôle de santé de la release      health.json
      (ou, en démonstration : livrer une release incomplète, sans health.json)
   4. Basculer le lien current vers la release X.Y.Z             lien temporaire + rename (atomique)
   5. Interroger /health jusqu'à obtenir la version X.Y.Z        uri : 1 appel + 5 nouvelles tentatives (2 s)
   6. Contrôler le statut et la version renvoyés par /health     status == ok, version == X.Y.Z
   7. Mémoriser la release active dans les facts locaux          /etc/ansible/facts.d/fleetinfo.fact
   8. Marquer le déploiement comme réussi                        statut SUCCES
                                         │
                       une tâche échoue  │
                                         ▼
 RESCUE
   1. Mémoriser la cause de l'échec                              tâche + message ; statut provisoire
   2. Rebasculer current vers la release précédente N-1          (si une N-1 différente existe)
   3. Recharger le service web                                   nginx reloaded (démarré s'il était arrêté)
   4. Confirmer le retour arrière par le contrôle de santé       bloc imbriqué (block + rescue) :
        a. Vérifier que /health répond de nouveau avec la version N-1
        b. Mémoriser le succès du retour arrière                  statut ECHEC_ROLLBACK_OK
        rescue : Mémoriser l'échec de la vérification             statut ECHEC_ROLLBACK_KO conservé
   5. Faire échouer explicitement le déploiement                 TOUJOURS atteint : message selon
                                                                 le statut (OK, KO, SANS_ROLLBACK)
                                         │
             toujours, succès ou échec   │
                                         ▼
 ALWAYS
   Tracer la tentative de déploiement dans le journal            1 ligne dans /var/log/fleetinfo/deploy.log
   (uniquement si quelque chose a été généré, basculé ou a échoué)
```

Points importants :

- **Pas de rechargement après la bascule** : nginx résout `current` à chaque requête (pas
  d'`open_file_cache`), la nouvelle release est servie immédiatement.
- Le contrôle `/health` part **du serveur lui-même** (`http://127.0.0.1:80/health`), à travers
  nginx : il ne dépend ni du firewall GCP ni du réseau Docker.
- Le fait local n'est écrit **qu'après** un contrôle de santé réussi : après un échec, il
  désigne toujours la release N-1 restaurée.
- Message de l'échec explicite, de la forme : `ÉCHEC du déploiement de Fleet Info 1.2.0 sur
  node1. Retour arrière effectué : la version 1.1.0 est de nouveau active et répond sur /health.
  Cause : ... Journal : /var/log/fleetinfo/deploy.log.`
- Sans release précédente (premier déploiement, ou mise à jour sur place de la version déjà
  active), aucun retour arrière n'est possible : le message l'indique et le statut est
  `ECHEC_SANS_ROLLBACK`.

## Format du journal de déploiement

Fichier `/var/log/fleetinfo/deploy.log` (root:adm, 0640 ; répertoire 0750) : une ligne par
tentative réelle, au format `clé=valeur`, ajoutée en fin de fichier.

```
<date UTC> hote=<hôte> type=<type> demandee=<version> precedente=<version|aucune> resultat=<résultat>[ detail="<cause>"]
```

| Champ | Valeurs |
|---|---|
| date | `AAAA-MM-JJTHH:MM:SSZ`, heure UTC du controller au moment de l'écriture |
| `hote` | `inventory_hostname` (`node1`, `fleetinfo-web-1`...) |
| `type` | `deploiement` (nouvelle release via `site.yml`), `rollback-manuel` (`rollback.yml`), `mise-a-jour-sur-place` (version déjà active, fichiers régénérés) |
| `demandee` | Version demandée |
| `precedente` | Version active avant l'opération, `aucune` au premier déploiement |
| `resultat` | `SUCCES` ; `ECHEC_ROLLBACK_OK` (échec, N-1 restaurée et vérifiée) ; `ECHEC_ROLLBACK_KO` (échec, et le retour arrière lui-même a échoué : **intervention manuelle requise**) ; `ECHEC_SANS_ROLLBACK` (échec, aucune version vers laquelle revenir) |
| `detail` | Uniquement en cas d'échec : tâche en échec et message ; pour `ECHEC_ROLLBACK_KO`, suivi de ` / retour arrière non confirmé : <message>` |
| `detail` | Présent en cas d'échec : `<nom de la tâche en échec> : <message>`, sur une ligne, guillemets doubles remplacés par des apostrophes, tronqué à 300 caractères |

Lignes réelles, relevées sur le banc local :

```
2026-11-03T18:09:57Z hote=node1 type=deploiement demandee=1.1.0 precedente=1.0.0 resultat=SUCCES
2026-11-03T18:10:46Z hote=node1 type=deploiement demandee=1.2.0 precedente=1.1.0 resultat=ECHEC_ROLLBACK_OK detail="Interroger /health jusqu'à obtenir la version 1.2.0 : Status code was 404 and not [200]: HTTP Error 404: Not Found"
```

Un passage sur un serveur déjà conforme (rien de généré, rien de basculé, aucun échec) n'est pas
une tentative et n'écrit rien : c'est ce qui permet `changed=0` au second passage.

Lecture :

```bash
# banc local, depuis socle-web-automatise/local/ sur le poste
docker compose exec node1 tail -n 5 /var/log/fleetinfo/deploy.log
# cloud, depuis socle-web-automatise/ sur le poste
ssh -i local/ssh/fleet_key ansible@<IP> sudo tail -n 5 /var/log/fleetinfo/deploy.log
```

Le compte d'exploitation `fleetops` (groupe `adm`, rôle `common`) peut aussi le lire sans sudo.

## Fait local `ansible_local.fleetinfo`

Fichier `/etc/ansible/facts.d/fleetinfo.fact` (JSON, root:root, 0644), généré par
`templates/fleetinfo.fact.j2` et relu automatiquement à chaque collecte des facts sous
`ansible_local.fleetinfo` ([ADR-13](../../../docs/decisions.md)).

Contenu constaté sur `node1` (banc local) :

```json
{
  "_ansible_managed": "Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : toute modification manuelle sera écrasée au prochain déploiement",
  "_source": "roles/fleetinfo/templates/fleetinfo.fact.j2",
  "version": "1.0.0",
  "previous_version": "1.3.0",
  "release_dir": "/opt/fleetinfo/releases/1.0.0",
  "deployed_at": "2026-11-03T18:13:25Z"
}
```

| Clé | Utilisée pour |
|---|---|
| `version`, `release_dir` | Information d'exploitation (release active selon le dernier déploiement réussi) |
| `previous_version` | Cible par défaut de `rollback.yml` ; affichée sur la page |
| `deployed_at` | Date « Dernier déploiement » de la page quand rien ne bascule : la page ne change pas d'un passage à l'autre |

Consultation depuis le controller :

```bash
ansible web -m ansible.builtin.setup -a filter=ansible_local
```

Résultat attendu (vérifié sur le banc local) : pour chaque hôte, `ansible_facts.ansible_local.fleetinfo`
avec `version`, `previous_version`, `release_dir`, `deployed_at` et `_source`. La clé
`_ansible_managed`, présente dans le fichier, n'apparaît pas dans cette sortie : Ansible écarte
des résultats de module les clés commençant par `_ansible_`.

## Point d'entrée `rollback` (retour arrière manuel)

Appel : `ansible-playbook rollback.yml` (release précédente mémorisée) ou
`ansible-playbook rollback.yml -e fleetinfo_rollback_version=1.0.0` (version précise) ; ajouter
`-i inventories/cloud/fleet.gcp.yml` pour le cloud. Même déploiement canari que `site.yml`.

| # | Tâche | Ce qu'elle fait |
|---|---|---|
| 0 | Validation des arguments (point d'entrée `rollback`) | Mêmes options que `main`, plus `fleetinfo_rollback_version`. |
| 1 | Déterminer la version cible du retour arrière | `fleetinfo_rollback_version` si renseignée, sinon `ansible_local.fleetinfo.previous_version`. |
| 2 | Vérifier qu'une version cible valide est connue | Cible non vide et au format `X.Y.Z`. |
| 3 | Lister les releases présentes sur le serveur | Pour le message d'erreur éventuel. |
| 4 | Vérifier la présence de la release complète X.Y.Z | `stat` de `releases/X.Y.Z/health.json`. |
| 5 | Refuser un retour arrière vers une release absente ou incomplète | Message listant les releases présentes. |
| 6 | Préparer l'arborescence de l'application | `prepare.yml`. |
| 7 | Rebasculer sans régénération vers la release X.Y.Z | `include_tasks: deploy.yml` avec `fleetinfo_version` = cible, `fleetinfo_render_release: false`, `fleetinfo_deploy_kind: rollback-manuel` : même bascule, même contrôle `/health`, même rescue, même journal. |

Comportement vérifié sur le banc local : depuis 1.2.0, `rollback.yml` rebascule vers 1.1.0 sans
régénérer les fichiers ; rejoué, il rebascule vers 1.2.0 (aller-retour entre les deux dernières
releases, car le fait local mémorise à chaque bascule la version quittée).

À savoir :

- La page restaurée est servie **telle qu'elle a été générée** : elle affiche la date de son
  déploiement initial, alors que le fait local enregistre la date du retour arrière. Le
  `site.yml` suivant (avec `fleetinfo_version` alignée sur la version restaurée) régénère donc la
  page une fois sur place (`changed=3`, ligne `type=mise-a-jour-sur-place` dans le journal), puis
  `changed=0` aux passages suivants (observé le 2026-11-04).
- Après un `rollback.yml`, **aligner `fleetinfo_version`** dans `group_vars/all/vars.yml` sur la
  version restaurée, sinon le prochain `site.yml` redéploie la version que l'on vient de quitter.
- Ne pas passer `-e fleetinfo_version=...` à `rollback.yml` : les extra vars l'emporteraient sur
  la cible imposée à `deploy.yml`. La tâche « Refuser une version imposée par -e pendant un
  retour arrière manuel » arrête alors le play avant toute bascule (vérifié le 2026-11-04).
  Utiliser uniquement `-e fleetinfo_rollback_version=...`.

## Mode simulation d'échec (démonstration)

```bash
ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0 -e fleetinfo_simulate_failure=true
```

La version passée doit être **différente** de la version active, sinon le garde-fou « Refuser
une simulation d'échec sur la version déjà active » arrête l'exécution (il n'existerait aucune
version vers laquelle revenir).

Ce qui se passe : la release 1.2.0 est générée **sans** `health.json` (tâche « Démonstration :
livrer une release incomplète (sans health.json) »), le lien bascule, nginx répond 404 sur
`/health`, le contrôle échoue après 6 interrogations (1 appel puis `fleetinfo_health_retries` = 5
nouvelles tentatives espacées de 2 s, soit une dizaine de secondes), le rescue rebascule vers la
version précédente,
recharge nginx, revérifie `/health`, puis échoue explicitement.

Résultat vérifié sur le banc local (version active 1.1.0) :

- `node1` (canari) : `failed=1`, `rescued=1` ; `/health` de nouveau en 1.1.0 ;
- `node2` : jamais touché par le play de déploiement (le canari a échoué, `max_fail_percentage: 0`) ;
- le site reste en ligne en 1.1.0 sur les deux nœuds ;
- journal : ligne `resultat=ECHEC_ROLLBACK_OK` avec la cause (voir plus haut) ;
- ensuite, un déploiement sain fonctionne normalement :
  `ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.2.0`.

## Ménage des releases

[`tasks/cleanup.yml`](tasks/cleanup.yml), exécuté à la fin de chaque passage du point d'entrée
`main`, sauf sur un hôte dont le déploiement a échoué (il n'est pas appelé par `rollback.yml`) :

1. lister les répertoires de `/opt/fleetinfo/releases/` ;
2. les trier par date de modification (`mtime`), du plus ancien au plus récent ;
3. retirer de la liste la release active (`fleetinfo_release_dir`) et la release précédente
   (`fleetinfo_recorded_previous`), **toujours protégées** ;
4. supprimer les plus anciennes, dans la limite du nombre de releases en excès par rapport à
   `fleetinfo_keep_releases`.

Rien n'est supprimé tant que le nombre de releases ne dépasse pas la limite (idempotent).
Vérifié sur le banc local : le déploiement d'une quatrième release (1.3.0) avec
`fleetinfo_keep_releases: 3` supprime 1.0.0, la plus ancienne non protégée.

## Déploiement canari

Porté par le play de `site.yml` (et de `rollback.yml`), pas par le rôle :

```yaml
serial:
  - 1
  - "100%"
max_fail_percentage: 0
```

Un premier serveur seul, puis tous les autres ensemble. Au premier échec, le play s'arrête : si
le canari échoue (et revient automatiquement à N-1), les autres serveurs ne reçoivent jamais la
version défectueuse.

## Variables

Valeurs par défaut : [`defaults/main.yml`](defaults/main.yml) (précédence la plus faible).
Toutes sont préfixées `fleetinfo_`.

| Variable | Défaut | Description |
|---|---|---|
| `fleetinfo_version` | `"1.0.0"` | Version à déployer (format `X.Y.Z`). Valeur de secours : la valeur de référence du socle est fixée **une fois** dans `group_vars/all/vars.yml`. |
| `fleetinfo_base_dir` | `/opt/fleetinfo` | Racine de l'application : `releases/<version>/` et lien `current` vers la release active. |
| `fleetinfo_keep_releases` | `3` | Nombre de releases conservées sur disque. La release active et la précédente ne sont jamais supprimées, quel que soit ce nombre. |
| `fleetinfo_environment` | `"{{ socle_env \| default('inconnu') }}"` | Environnement affiché (`local` / `cloud`), fourni par les `group_vars` de chaque inventaire. |
| `fleetinfo_cloud_zone` | `""` | Zone GCP affichée, renseignée par `inventories/cloud/group_vars/all.yml`. Vide : la section « Cloud » de la page est absente (local). |
| `fleetinfo_cloud_machine_type` | `""` | Type de machine GCP affiché (vide = non affiché). |
| `fleetinfo_cloud_public_ip` | `""` | IP publique affichée (vide = non affichée). |
| `fleetinfo_release_notes` | `"1.0.0"`, `"1.1.0"`, `"1.2.0"` | Notes de version affichées sur la page (`dict` version → texte). Une version absente de ce catalogue reste déployable : la section « Notes de version » est simplement omise. À compléter ici, ou à surcharger dans `group_vars/all/vars.yml`, lors d'une livraison. |
| `fleetinfo_health_host` | `127.0.0.1` | Hôte interrogé par le contrôle de santé, depuis le serveur lui-même, à travers nginx. |
| `fleetinfo_health_port` | `80` | Port interrogé par le contrôle de santé. |
| `fleetinfo_health_path` | `/health` | Chemin du contrôle de santé. |
| `fleetinfo_health_retries` | `5` | Nombre de nouvelles tentatives (`retries` du module `uri`) après le premier appel : 6 interrogations au total avant de déclarer la release défaillante. |
| `fleetinfo_health_delay` | `2` | Secondes entre deux interrogations. |
| `fleetinfo_web_service` | `nginx` | Service web rechargé lors d'un retour arrière automatique. |
| `fleetinfo_deploy_log` | `/var/log/fleetinfo/deploy.log` | Journal des déploiements : une ligne par tentative. |
| `fleetinfo_log_group` | `adm` | Groupe propriétaire du journal : permet au compte d'exploitation (rôle `common`) de le lire. |
| `fleetinfo_simulate_failure` | `false` | `true` : la release produite est volontairement incomplète (pas de `health.json`) et le retour arrière se déclenche. À passer uniquement en ligne de commande, avec une version différente de la version active. |
| `fleetinfo_rollback_version` | `""` | Version cible de `rollback.yml` ; vide = release précédente, mémorisée lors du dernier déploiement réussi. |

Surcharges appliquées par le socle :

| Variable | Valeur | Où |
|---|---|---|
| `fleetinfo_version` | `"1.0.0"` | `group_vars/all/vars.yml` (seul endroit à modifier pour livrer une version) |
| `fleetinfo_base_dir` | `"{{ socle_app_root }}"` (`/opt/fleetinfo`) | `group_vars/all/vars.yml` |
| `fleetinfo_health_port` | `"{{ socle_http_port }}"` (`80`) | `group_vars/all/vars.yml` |
| `fleetinfo_cloud_zone` | `"{{ gce_zone }}"` | `inventories/cloud/group_vars/all.yml` |
| `fleetinfo_cloud_machine_type` | `"{{ gce_machineType }}"` | `inventories/cloud/group_vars/all.yml` |
| `fleetinfo_cloud_public_ip` | `"{{ ansible_host }}"` | `inventories/cloud/group_vars/all.yml` |

## Constantes internes

[`vars/main.yml`](vars/main.yml) (précédence forte). Les chemins dérivent de
`fleetinfo_base_dir` et `fleetinfo_version`, évalués à l'usage.

| Variable | Valeur | Description |
|---|---|---|
| `fleetinfo_releases_dir` | `"{{ fleetinfo_base_dir }}/releases"` | Répertoire des releases. |
| `fleetinfo_current_link` | `"{{ fleetinfo_base_dir }}/current"` | Lien vers la release active. |
| `fleetinfo_release_dir` | `"{{ fleetinfo_releases_dir }}/{{ fleetinfo_version }}"` | Répertoire de la release demandée. |
| `fleetinfo_fact_dir` | `/etc/ansible/facts.d` | Répertoire des faits locaux. |
| `fleetinfo_fact_file` | `"{{ fleetinfo_fact_dir }}/fleetinfo.fact"` | Fait local (release active, précédente, date). |
| `fleetinfo_health_url` | `"http://{{ fleetinfo_health_host }}:{{ fleetinfo_health_port }}{{ fleetinfo_health_path }}"` | URL du contrôle de santé. |
| `fleetinfo_render_release` | `true` | Générer les fichiers de la release avant la bascule ; `rollback.yml` le passe à `false` (paramètre d'include, précédence supérieure). |
| `fleetinfo_deploy_kind` | `deploiement` | Type d'opération écrit dans le journal ; `rollback.yml` le passe à `rollback-manuel`. |
| `fleetinfo_version_pattern` | `'^[0-9]+\.[0-9]+\.[0-9]+$'` | Format accepté pour une version. |

Variables calculées pendant l'exécution (`set_fact`) : `fleetinfo_active_dir`,
`fleetinfo_active_version`, `fleetinfo_deploy_needed`, `fleetinfo_deployed_at`,
`fleetinfo_recorded_previous`, `fleetinfo_deploy_status`, `fleetinfo_deploy_detail`,
`fleetinfo_rollback_target`. Description dans la
[référence des variables](../../../docs/variables.md#53-rôle-fleetinfo).

## Handlers

**Aucun**, volontairement ([`handlers/main.yml`](handlers/main.yml) contient une liste vide) :

- la bascule de release est un simple changement du lien `current`, que nginx résout à chaque
  requête : aucun rechargement n'est nécessaire pour servir la nouvelle version ;
- le seul rechargement du rôle (tâche « Recharger le service web » du rescue) doit avoir lieu
  **immédiatement**, avant de revérifier `/health` ; un handler, exécuté en fin de play,
  arriverait trop tard. C'est un reload et non un restart : il ne coupe pas les connexions en
  cours et démarre nginx s'il était arrêté.

## Fichiers générés sur le serveur

| Fichier | Source | En-tête |
|---|---|---|
| `/opt/fleetinfo/releases/<version>/index.html` | `templates/index.html.j2` | Deux commentaires HTML : `<!-- Géré par Ansible (socle-web-automatise) - NE PAS MODIFIER À LA MAIN : ... -->` et `<!-- Source : roles/fleetinfo/templates/index.html.j2 (rôle fleetinfo, release <version>) -->` |
| `/opt/fleetinfo/releases/<version>/health.json` | `templates/health.json.j2` | Clés JSON `"_ansible_managed"` et `"_source": "roles/fleetinfo/templates/health.json.j2"` (JSON n'a pas de commentaires) |
| `/etc/ansible/facts.d/fleetinfo.fact` | `templates/fleetinfo.fact.j2` | Clés `"_ansible_managed"` et `"_source"` |
| `/opt/fleetinfo/current` | module `file` (`state: link`) | lien symbolique vers `/opt/fleetinfo/releases/<version>` |
| `/var/log/fleetinfo/deploy.log` | module `lineinfile` | aucun : journal en ajout seul (root:adm, 0640) |

Réponse de `/health` constatée sur `node1` :

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

Contenu de la page d'accueil, entièrement calculé depuis les facts et les variables :

| Section | Champs |
|---|---|
| En-tête | Nom d'hôte, FQDN, badges environnement / version / distribution ; couleur verte en local, bleue sur le cloud |
| Identité | Nom d'hôte, FQDN, IP principale, adresses IPv4, IP publique (cloud uniquement), groupes Ansible |
| Système | Distribution et version, noyau, architecture, virtualisation, gestionnaire de services |
| Ressources | vCPU, mémoire totale (`human_readable`), swap (si présent), disque racine (si connu) |
| Cloud · Google Compute Engine | Zone, type de machine. **Absente** si `fleetinfo_cloud_zone` et `fleetinfo_cloud_machine_type` sont vides (local) : aucun champ vide, aucune erreur |
| Déploiement | Version, dernier déploiement (UTC), version précédente (si connue), répertoire de release, notes de version (si présentes au catalogue) |

Règle d'idempotence du template : n'afficher que des valeurs **stables** d'une exécution à
l'autre (ni heure courante, ni charge, ni uptime, ni espace libre).

Sur GCE, le FQDN affiché est en principe le nom DNS interne de la VM, qui contient l'identifiant
du projet (`<vm>.<zone>.c.<project_id>.internal`) ; la page étant publique en HTTP, cet
identifiant y est visible (résultat attendu, à confirmer lors de la répétition générale).

Vérification (depuis `socle-web-automatise/local/` sur le poste) :

```bash
curl -s http://localhost:8081/health
docker compose exec node1 head -n 2 /opt/fleetinfo/current/index.html
docker compose exec node1 ls -l /opt/fleetinfo /opt/fleetinfo/releases
```

Résultat attendu : le JSON ci-dessus (version déployée) ; les deux commentaires d'en-tête ;
`current -> /opt/fleetinfo/releases/<version>` et au plus `fleetinfo_keep_releases`
répertoires de release.

## Dépendances

| Type | Dépendance | Détail |
|---|---|---|
| Rôle | aucun | `dependencies: []` ; volontairement pas de dépendance `meta` sur `webserver` : chaque rôle reste lisible et rejouable seul, l'ordre des couches est porté par `site.yml` |
| Prérequis fonctionnel | un serveur web qui sert `fleetinfo_base_dir/current` sur `fleetinfo_health_port`, avec `/health` → `health.json` | Fourni par le rôle `webserver`, joué avant `fleetinfo` par `site.yml` |
| Collections | aucune | Uniquement des modules `ansible.builtin` (`assert`, `stat`, `set_fact`, `file`, `template`, `uri`, `service`, `fail`, `lineinfile`, `find`) |
| Moteur | ansible-core 2.17 | `min_ansible_version: "2.17"` |
| Système cible | Debian 12, systemd, groupe `adm` | Le groupe `adm` existe sur Debian ; le compte `fleetops` y est ajouté par `common` |

## Exemple d'utilisation

Extrait de `site.yml` (troisième play) :

```yaml
- name: Déployer l'application Fleet Info
  hosts: web
  become: true
  serial:
    - 1
    - "100%"
  max_fail_percentage: 0
  roles:
    - role: fleetinfo
      tags: [fleetinfo]
```

Extrait de `rollback.yml` :

```yaml
- name: Revenir à une version précédente de Fleet Info
  hosts: web
  become: true
  serial:
    - 1
    - "100%"
  max_fail_percentage: 0
  tasks:
    - name: Rebasculer vers la release cible
      ansible.builtin.include_role:
        name: fleetinfo
        tasks_from: rollback
```

Commandes courantes, dans le controller (`/workspace/ansible`) ; ajouter
`-i inventories/cloud/fleet.gcp.yml` pour le cloud :

```bash
ansible-playbook site.yml --tags fleetinfo                                     # version de vars.yml
ansible-playbook site.yml --tags fleetinfo -e fleetinfo_version=1.1.0          # version ponctuelle
ansible-playbook site.yml --tags fleetinfo --check --diff                      # simulation
ansible-playbook rollback.yml                                                  # retour à N-1
ansible-playbook rollback.yml -e fleetinfo_rollback_version=1.0.0              # retour à une version précise
```

## Idempotence

- La date affichée n'est **jamais** « maintenant » à chaque passage : elle ne change qu'au
  moment d'une bascule et est relue ensuite dans le fait local ([ADR-13](../../../docs/decisions.md)).
- Les templates n'utilisent que des facts stables ; `ansible_managed` n'a ni date ni chemin.
- Le lien `current` n'est modifié que s'il pointe ailleurs.
- Le journal n'est écrit que pour une tentative réelle.
- Le ménage ne supprime rien tant que la limite n'est pas dépassée.

Vérifié sur le banc local : second passage de `site.yml`, `node1` `ok=39 changed=0` et `node2`
`ok=39 changed=0`, `failed=0`.

Mode `--check` : sur des serveurs conformes, `changed=0` et `failed=0` ; avec une nouvelle
version, les changements sont annoncés sans erreur (la bascule est forcée en simulation car le
répertoire de release n'est pas réellement créé, et le contrôle `/health` est sauté). Sur un
serveur vierge, `site.yml --check` échoue dès les rôles précédents (paquets absents) : c'est
normal.

## Licence et auteur

Licence MIT. Auteur : Équipe Plateforme NovaRetail (`namespace: novaretail`, `meta/main.yml`).
