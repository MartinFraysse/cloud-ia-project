# Rôle `common`

## Objectif
Socle appliqué à tout serveur : paquets de base, fuseau horaire,
utilisateur d'exploitation (sans sudo), bannière de connexion.

## Variables
| Variable | Défaut | Description |
|---|---|---|
| `common_packages` | curl, vim, ca-certificates, tzdata | Paquets de base |
| `common_timezone` | Europe/Paris | Fuseau horaire IANA |
| `common_ops_user` | fleetops | Compte d'exploitation |
| `common_ops_user_groups` | adm, systemd-journal | Lecture des journaux (moindre privilège) |
| `common_environment` | `{{ socle_env }}` | Environnement affiché |
| `common_motd_footer` | (texte) | Pied de bannière |

## Dépendances
- Collection `community.general` (module `timezone`), cf. `requirements.yml`.
- Cible avec systemd + dbus (timedatectl).

## Exemple
    - hosts: web
      become: true
      roles:
        - role: common
          vars:
            common_timezone: "UTC"