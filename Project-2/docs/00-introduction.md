# Introduction

## Le contexte

**Cloud Hôtels** (une quarantaine d'hôtels) propose un **livre d'or numérique**.
En fin de séjour, le client écrit un message. Le message s'affiche dans le hall de l'hôtel.

Le premier prototype était installé à la main sur un poste.
Lors d'une démonstration, un redémarrage a **effacé tous les messages**.

## L'application

L'application est **Guestbook**, un exemple officiel de Kubernetes. Elle a **3 composants** :

```mermaid
flowchart LR
    C(["👤 Client"]) ==> F["🖥️ <b>frontend</b><br/>site web PHP"]
    F ==>|"① écrit"| L["📕 <b>redis-leader</b><br/>base principale"]
    F ==>|"② lit"| R["📗 <b>redis-follower</b><br/>copies de la base"]
    L ==>|"③ recopie"| R

    classDef user fill:#374151,stroke:#d1d5db,color:#fff
    classDef fe fill:#6d28d9,stroke:#c4b5fd,color:#fff
    classDef leader fill:#b91c1c,stroke:#fca5a5,color:#fff
    classDef follower fill:#15803d,stroke:#86efac,color:#fff
    class C user
    class F fe
    class L leader
    class R follower
```

| Composant | Rôle |
|---|---|
| **frontend** | Site web PHP : affiche et enregistre les messages |
| **redis-leader** | Base principale : reçoit **les écritures** |
| **redis-follower** | Copies de la base : servent **les lectures** |

## Les objectifs du projet

| # | Objectif | Comment |
|---|---|---|
| 1 | **Ne plus perdre aucun message** | La base écrit sur un disque persistant |
| 2 | **Héberger l'application dans le cloud** | Un cluster Kubernetes managé par Google (GKE) |
| 3 | **Créer le cluster en code** | Terraform |
| 4 | **3 environnements isolés** : `dev`, `staging`, `prod` | Un seul chart Helm, des réglages différents |
| 5 | **Pouvoir travailler en local** | minikube, avec le même chart que dans le cloud |
| 6 | **Aucun réglage écrit en dur** | ConfigMaps et fichiers de valeurs Helm |

> **Règle de base :** Terraform crée le cluster. Helm installe l'application dedans.
> Les deux outils ne se chevauchent jamais.

## Vue d'ensemble

```mermaid
flowchart TB
    G[("📦 <b>Dépôt Git</b>")]

    subgraph LOCAL["💻 EN LOCAL (poste de travail)"]
        MK[["☸️ Cluster <b>minikube</b>"]]
    end

    subgraph CLOUD["☁️ DANS GOOGLE CLOUD"]
        TF["🏗️ <b>Terraform</b>"] ==>|crée| GKE[["☸️ Cluster <b>GKE</b>"]]
    end

    G ==>|"⎈ même chart Helm"| MK
    G ==> TF
    G ==>|"⎈ même chart Helm"| GKE

    classDef git fill:#374151,stroke:#d1d5db,color:#fff
    classDef tf fill:#be185d,stroke:#f9a8d4,color:#fff
    classDef cluster fill:#1d4ed8,stroke:#93c5fd,color:#fff
    class G git
    class TF tf
    class MK,GKE cluster
```

Dans chaque cluster, l'application est installée **3 fois**, une par environnement (un namespace chacun) :

| Environnement | Rôle | Namespace | Installation Helm |
|---|---|---|---|
| **dev** | Tests des développeurs | `dev` | `stack-dev` |
| **staging** | Répétition avant la production | `staging` | `stack-staging` |
| **prod** | Utilisé par les clients | `prod` | `stack-prod` |

## Automatisé ou manuel

| ✅ Automatisé (code dans le dépôt) | ✋ Manuel (documenté ici) |
|---|---|
| Création du cluster GKE (Terraform) | Installation des outils sur le poste |
| Installation de l'application (Helm) | Ouverture d'une session de lab Google |
| Configuration des 3 environnements | Connexion au compte Google (`gcloud auth login`) |
| Mises à jour et retours arrière (Helm) | Saisie de l'ID du projet dans `terraform.tfvars` |

## Organisation du dépôt

```
Project-2/
├── docs/          → documentation et captures d'écran
├── k8s/           → manifestes Kubernetes de base (parties 3 et 4)
├── helm/          → chart Helm (parties 5 et 6)
└── terraform/     → création du cluster GKE (partie 7)
```

---

[🏠 Sommaire](README.md) · [Partie 1 — Préparer le poste ➡️](01-preparation-poste.md)
