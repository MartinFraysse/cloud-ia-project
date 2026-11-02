# Captures d'écran — Projet 2

Captures d'écran des étapes du projet, utilisées par la documentation de transfert et pour l'oral.
Convention de nommage : `NN-sujet-court.png` (NN = ordre chronologique).

| # | Fichier | Étape | Ce que montre la capture |
|---|---------|----------------|--------------------------|
| 01 | `01-installation-outils-pacman.png` | 01-preparer | Installation des outils |
| 02 | `02-installation-gcloud-yay.png` | 01-preparer | Installation de gcloud + plugin GKE (AUR) |
| 03 | `03-demarrage-minikube.png` | 01-preparer | Démarrage du cluster local minikube, nœud Ready |

---

## 01 — Installation des outils (pacman)

- **Fichier :** `01-installation-outils-pacman.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-préparation-outils`
- **Commande :** `sudo pacman -S --needed kubectl helm minikube terraform`
- **Versions installées :**
  - kubectl 1.37.1-1
  - helm 4.3.0-1
  - minikube 1.38.1-2
  - terraform 1.15.9-1
- **Volume :** 78,67 MiB téléchargés, 377,54 MiB installés.
- **Commentaire :** preuve de la préparation du poste (Arch Linux). L'option
  `--needed` évite de réinstaller un paquet déjà à jour. Utile dans la doc pour
  la section « Prérequis » et pour justifier les versions des outils.

---

## 02 — Installation de gcloud et du plugin GKE (yay / AUR)

- **Fichier :** `02-installation-gcloud-yay.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-préparation-outils`
- **Commande :** `yay -S google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin`
- **Paquets (AUR) :**
  - `google-cloud-cli` 591.0.0-1
  - `google-cloud-cli-gke-gcloud-auth-plugin` 542.0.0-1
- **Vérification :** `gcloud version` et `gke-gcloud-auth-plugin --version`.
- **Erreur rencontrée :** une première tentative avait échoué à cause d'une faute de frappe dans
  le nom du plugin (`google-coud-…`) → `No AUR package found`.
- **Commentaire :** le plugin `gke-gcloud-auth-plugin` est obligatoire pour que kubectl
  s'authentifie sur GKE (depuis Kubernetes 1.26). Utile pour la section « Prérequis » et la
  section « Erreurs rencontrées » de la doc.

---

## 03 — Démarrage du cluster local minikube

- **Fichier :** `03-demarrage-minikube.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-préparation-outils`
- **Commandes :** `minikube start --driver=docker` puis `kubectl get nodes`
- **Résultat :**
  - minikube v1.38.1, driver Docker, nœud `minikube` (2 CPU, 3900 Mo de RAM).
  - Kubernetes **v1.35.1** sur Docker 29.2.1, réseau bridge CNI.
  - Addons activés : `storage-provisioner` et `default-storageclass` → c'est la **StorageClass
    par défaut** (`standard`) qui créera le disque de Redis à l'étape 4.
  - `kubectl get nodes` → `minikube   Ready   control-plane   v1.35.1`.
- **Avertissements (non bloquants) :**
  - minikube 1.39 passera par défaut au runtime `containerd` (sans impact ici).
  - Nouvelle version minikube 1.39.0 disponible (non nécessaire).
  - kubectl 1.37.1 vs cluster 1.35.1 : écart de 2 versions mineures (Kubernetes garantit ±1).
    Sans impact pour les commandes de base ; sinon utiliser `minikube kubectl -- <commande>`.
- **Commentaire :** preuve que l'environnement local fonctionne (section « Prérequis » et
  « Déploiement local » de la doc). À noter dans les versions testées : Kubernetes 1.35.1.
