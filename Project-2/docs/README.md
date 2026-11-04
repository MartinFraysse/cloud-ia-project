# Livre d'or Cloud — Documentation de transfert

> **Pour qui ?** Pour l'équipe qui reprend l'exploitation de la plateforme.
> **Objectif :** pouvoir tout réinstaller, utiliser et faire évoluer **avec cette seule documentation**.

La documentation est découpée **en un fichier par partie**. Lire dans l'ordre la première fois.

## Sommaire

| # | Fichier | Contenu | État |
|---|---|---|---|
| 0 | [Introduction](00-introduction.md) | Le projet, ses objectifs, ce qui est automatisé | ✅ |
| 1 | [Préparer le poste de travail](01-preparation-poste.md) | Outils, versions, cluster local | ✅ |
| 2 | [Constater le problème](02-constater-le-probleme.md) | L'application d'origine et la perte des messages | ✅ |
| 3 | [Les manifestes Kubernetes](03-manifestes-kubernetes.md) | Les objets de l'application | ✅ |
| 4 | [La persistance des données](04-persistance-des-donnees.md) | Ne plus perdre de messages | ✅ |
| 5 | [Le chart Helm](05-chart-helm.md) | Un seul chart pour tous les environnements | ✅ |
| 6 | [Les environnements dev / staging / prod](06-environnements-dev-staging-prod.md) | Installation, mise à jour, retour arrière | ✅ |
| 7 | Le cluster GKE avec Terraform | Création du cluster dans Google Cloud | ⏳ à venir |
| 8 | Le déploiement dans le cloud | Connexion au cluster et mise en ligne | ⏳ à venir |
| 9 | Exploitation | Runbooks, dépannage, limites connues | ⏳ à venir |

## En une phrase

> **Terraform crée le cluster Kubernetes dans Google Cloud. Helm y installe l'application
> Guestbook en 3 environnements (`dev`, `staging`, `prod`). Le même chart fonctionne en local
> sur minikube.**

## Code couleur des schémas

Les schémas de la documentation utilisent toujours les mêmes couleurs.

| Couleur | Signification |
|---|---|
| 🟪 violet | Le **site web** (`frontend`) |
| 🟥 rouge | La **base principale** (`redis-leader`) |
| 🟩 vert | Les **copies** de la base (`redis-follower`) |
| 🔷 cyan | Un **Service** (adresse fixe) |
| 🟦 bleu | Un **Deployment**, un ReplicaSet ou un **cluster** |
| 🟨 jaune | Une **ConfigMap** (réglages) |
| 🟧 orange | Le **stockage** : PVC et PV (disque persistant) |
| ⬜ blanc | Un **pod** |
| 🩷 rose | **Terraform** |
| ⬛ gris | Une personne, un outil en ligne de commande, le poste ou le dépôt Git |

Flèche **épaisse** = flux principal · flèche **pointillée** = réglage ou connexion.

## Autres ressources

| Dossier / fichier | Contenu |
|---|---|
| [`screenshots/`](screenshots/) | Captures d'écran des étapes, décrites dans [`screenshots/README.md`](screenshots/README.md) |
