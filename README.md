# Cloud & IaC — Projets d'équipe

Projets du module **Cloud & Infrastructure as Code** (ESIEA, S9).

| Projet | Sujet | Outils |
|---|---|---|
| [Project-1](Project-1/) | Socle Web Automatisé : déploiement de l'application *Fleet Info* sur GCP et en local | Terraform, Ansible, Docker Compose |
| [Project-2](Project-2/) | Déploiement de l'application *Guestbook* en `dev` / `staging` / `prod` | Kubernetes, Helm, minikube |

## Organisation du dépôt

```
.
├── Project-1/
│   ├── README.md        → documentation de transfert
│   ├── docs/            → schémas, décisions techniques, runbooks
│   ├── terraform/       → infrastructure GCP (VPC, firewall, VM)
│   ├── local/           → environnement local Docker Compose
│   └── ansible/         → configuration des serveurs et déploiement
└── Project-2/
    ├── k8s/             → manifestes Kubernetes
    └── helm/guestbook/  → chart Helm
```

## Stratégie de branches : trunk-based development

- `main` est l'unique branche de référence (le *trunk*) : elle doit **toujours fonctionner**.
- Chaque modification se fait sur une **branche courte**, créée depuis `main` et fusionnée en
  **moins de 2 jours**.
- Pas de branche `develop` ni de branche de release : on intègre souvent et par petits morceaux.
- Une fonctionnalité trop longue est découpée en plusieurs petites Pull Requests.

## Convention de nommage des branches

Format : `<type>/<projet>-<description-courte>`

| Type | Usage | Exemple |
|---|---|---|
| `feat/` | nouvelle fonctionnalité | `feat/p1-terraform-network` |
| `fix/` | correction de bug | `fix/p1-nginx-handler` |
| `docs/` | documentation | `docs/p1-runbook-rollback` |
| `refactor/` | réorganisation sans changement de comportement | `refactor/p2-helm-helpers` |
| `chore/` | maintenance (dépendances, `.gitignore`…) | `chore/update-gitignore` |

En minuscules, avec des tirets, sans accent.

## Règle de merge

- Pas de push direct sur `main` : tout passe par une **Pull Request**.
- **1 relecture approuvée** par un autre membre de l'équipe est obligatoire.
- La branche est **à jour avec `main`** avant le merge.
- Merge en **Squash and merge** : un commit propre par PR sur `main`. La branche est supprimée
  après le merge.

## Workflow type

```bash
# 1. Partir de main à jour
git switch main
git pull

# 2. Créer une branche courte
git switch -c feat/p1-terraform-network

# 3. Travailler et commiter par petites étapes
git add .
git commit -m "feat(terraform): ajouter le module network"

# 4. Se remettre à jour avec main avant de pousser
git fetch origin
git rebase origin/main

# 5. Pousser et ouvrir la Pull Request
git push -u origin feat/p1-terraform-network
gh pr create --fill

# 6. Après approbation : Squash and merge sur GitHub, puis nettoyage en local
git switch main
git pull
git branch -D feat/p1-terraform-network   # -D : après un squash, Git ne voit pas la branche comme fusionnée
```

## Équipe

| Membre | GitHub |
|---|---|
| Martin Fraysse | [@MartinFraysse](https://github.com/MartinFraysse) |
| Alexis Fournier | [@MJpyroman](https://github.com/MJpyroman) |
| Louis Bertin | [@LouisBertin40](https://github.com/LouisBertin40) |
| Youssouf Mbami | [@youssouf95](https://github.com/youssouf95) |
| Martin Launes | [@launeseseia](https://github.com/launeseseia) |
