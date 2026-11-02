# Livre d'or Cloud — Documentation de transfert

> **Pour qui ?** Pour l'équipe qui reprend l'exploitation de la plateforme.
> **Objectif :** pouvoir tout réinstaller, utiliser et faire évoluer **avec cette seule documentation**.

La documentation est découpée **en un fichier par partie**. Lire dans l'ordre la première fois.

## Sommaire

| # | Fichier | Contenu | État |
|---|---|---|---|
| 0 | [Introduction](00-introduction.md) | Le projet, ses objectifs, ce qui est automatisé | ✅ |
| 1 | [Préparer le poste de travail](01-preparation-poste.md) | Outils, versions, cluster local | ✅ |
| 2 | Constater le problème | L'application d'origine et la perte des messages | ⏳ à venir |
| 3 | Les manifestes Kubernetes | Les objets de l'application | ⏳ à venir |
| 4 | La persistance des données | Ne plus perdre de messages | ⏳ à venir |
| 5 | Le chart Helm | Une seule recette pour tous les environnements | ⏳ à venir |
| 6 | Les environnements dev / staging / prod | Installation, mise à jour, retour arrière | ⏳ à venir |
| 7 | Le cluster GKE avec Terraform | Création du cluster dans Google Cloud | ⏳ à venir |
| 8 | Le déploiement dans le cloud | Connexion au cluster et mise en ligne | ⏳ à venir |
| 9 | Exploitation | Runbooks, dépannage, limites connues | ⏳ à venir |

## En une phrase

> **Terraform crée le cluster Kubernetes dans Google Cloud. Helm y installe l'application
> Guestbook en 3 environnements (`dev`, `staging`, `prod`). Le même chart fonctionne en local
> sur minikube.**

## Autres ressources

| Dossier / fichier | Contenu |
|---|---|
| [`screenshots/`](screenshots/) | Captures d'écran des étapes, décrites dans [`screenshots/README.md`](screenshots/README.md) |
