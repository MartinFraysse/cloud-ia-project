# Captures d'écran — Projet 2

Captures d'écran des étapes du projet, utilisées par la documentation de transfert et pour l'oral.
Convention de nommage : `NN-sujet-court.png` (NN = ordre chronologique).

| # | Fichier | Étape | Ce que montre la capture |
|---|---------|----------------|--------------------------|
| 01 | `01-installation-outils-pacman.png` | 01-preparer | Installation des outils |
| 02 | `02-installation-gcloud-yay.png` | 01-preparer | Installation de gcloud + plugin GKE (AUR) |
| 03 | `03-demarrage-minikube.png` | 01-preparer | Démarrage du cluster local minikube, nœud Ready |
| 04 | `04-deploiement-tutoriel-origine.png` | 02-voir-le-bug | Déploiement de l'application d'origine dans le namespace `tuto` |
| 05 | `05-etat-application-origine.png` | 02-voir-le-bug | `kubectl get all -n tuto` : 6 pods Running, Services, Deployments, ReplicaSets |
| 06 | `06-minikube-tunnel.png` | 02-voir-le-bug | `minikube tunnel` actif : accès au Service LoadBalancer `frontend` |
| 07 | `07-ip-externe-frontend.png` | 02-voir-le-bug | Le Service `frontend` reçoit son `EXTERNAL-IP` grâce au tunnel |
| 08 | `08-messages-avant-suppression.png` | 02-voir-le-bug | Le livre d'or avec 3 messages, avant la suppression du pod leader |
| 09 | `09-suppression-pod-leader.png` | 02-voir-le-bug | Suppression du pod `redis-leader` |
| 10 | `10-messages-perdus.png` | 02-voir-le-bug | Après redémarrage du leader : **tous les messages ont disparu** |
| 11 | `11-creation-fichiers-manifestes.png` | 03-fichiers-propres | Création des 9 fichiers de manifestes (vides) dans `k8s/` |
| 12 | `12-apply-manifestes-dev.png` | 03-fichiers-propres | Installation de nos manifestes dans le namespace `dev` |
| 13 | `13-etat-manifestes-dev.png` | 03-fichiers-propres | `kubectl get all,cm -n dev` : 5 pods Running, 3 Services, 2 ConfigMaps |
| 14 | `14-endpoints-dev.png` | 03-fichiers-propres | Endpoints non vides : chaque Service trouve ses pods |
| 15 | `15-application-dev-fonctionnelle.png` | 03-fichiers-propres | L'application déployée avec nos manifestes fonctionne (3 messages) |
| 16 | `16-apply-persistance-dev.png` | 04-reparer-le-bug | Installation de la persistance dans `dev` : PVC `Bound` (1Gi, RWO, `standard`), leader redéployé |
| 17 | `17-messages-avant-suppression-persistance.png` | 04-reparer-le-bug | Le livre d'or avec 3 messages, avant la suppression du pod leader |
| 18 | `18-redis-get-avant-suppression.png` | 04-reparer-le-bug | `redis-cli GET guestbook` : les 3 messages sont dans Redis |
| 19 | `19-verification-config-redis.png` | 04-reparer-le-bug | `CONFIG GET dir` → `/data`, `appendonly` → `yes`, fichiers de données dans `/data` |
| 20 | `20-suppression-pod-leader-persistance.png` | 04-reparer-le-bug | Suppression du pod leader, le nouveau pod passe `1/1 Running` |
| 21 | `21-messages-conserves-apres-suppression.png` | 04-reparer-le-bug | Après actualisation : **les 3 messages sont toujours là** ✅ |
| 22 | `22-redis-get-apres-suppression.png` | 04-reparer-le-bug | `redis-cli GET guestbook` dans le nouveau pod : mêmes 3 messages |
| 23 | `23-recreate-ordre-des-pods.png` | 04-reparer-le-bug | Stratégie `Recreate` : l'ancien pod leader s'arrête **avant** que le nouveau soit créé |
| 24 | `24-redis-get-apres-recreate.png` | 04-reparer-le-bug | Après la mise à jour du leader : les 3 messages sont toujours là |
| 25 | `25-redemarrage-minikube-pods.png` | 04-reparer-le-bug | Redémarrage complet de minikube : les 5 pods reviennent `1/1 Running` |
| 26 | `26-redis-get-apres-redemarrage-minikube.png` | 04-reparer-le-bug | Après le redémarrage complet : les 3 messages sont toujours là |
| 27 | `27-helm-lint-chart.png` | 05-recette-helm | `helm lint` du chart : 0 échec |
| 28 | `28-helm-lint-install-environnements.png` | 06-trois-environnements | `helm lint` + `helm install` de dev, staging et prod : 3 releases `deployed` |
| 29 | `29-helm-list-trois-releases.png` | 06-trois-environnements | `helm list -A` : 3 releases (dev, staging, prod) en révision 1 |
| 30 | `30-kubectl-get-all-prod.png` | 06-trois-environnements | contenu du namespace `prod` : 3 frontends, 2 followers, 1 leader, PVC 5Gi `Bound` |
| 31 | `31-kubectl-get-all-dev.png` | 06-trois-environnements | contenu du namespace `dev` après nettoyage : 1 pod par composant, port 8080, PVC 1Gi |
| 32 | `32-kubectl-get-all-staging.png` | 06-trois-environnements | contenu du namespace `staging` : 2 frontends, port 8081, PVC 1Gi |
| 33 | `33-minikube-tunnel-ip-trois-environnements.png` | 06-trois-environnements | `minikube tunnel` + `EXTERNAL-IP` des 3 frontends (ports 8080 / 8081 / 80) |
| 34 | `34-values-staging-replicas-3.png` | 06-trois-environnements | `values-staging.yaml` : `frontend.replicaCount` passé de 2 à 3 |
| 35 | `35-helm-upgrade-staging-replicas.png` | 06-trois-environnements | `helm upgrade stack-staging` : révision 3, frontend 3 pods sans toucher aux templates |
| 36 | `36-idempotence-prod-pods-avant.png` | 06-trois-environnements | idempotence (1/4) : pods de `prod` **avant** l'upgrade |
| 37 | `37-idempotence-prod-helm-upgrade.png` | 06-trois-environnements | idempotence (2/4) : `helm upgrade stack-prod` sans changement → révision 2 |
| 38 | `38-idempotence-prod-pods-apres.png` | 06-trois-environnements | idempotence (3/4) : pods de `prod` **après** : les mêmes, aucun recréé |
| 39 | `39-idempotence-prod-helm-history.png` | 06-trois-environnements | idempotence (4/4) : `helm history stack-prod` : révisions 1 et 2 |
| 40 | `40-upgrade-version-prod-rolling-update.png` | 06-trois-environnements | montée du chart en 0.2.0 (1/3) : `kubectl get pods -n prod -w`, remplacement de tous les pods |
| 41 | `41-upgrade-version-prod-helm-history.png` | 06-trois-environnements | montée du chart en 0.2.0 (2/3) : `helm history` → révision 3, `guestbook-0.2.0` |
| 42 | `42-upgrade-version-prod-message-conserve.png` | 06-trois-environnements | montée du chart en 0.2.0 (3/3) : « Voici la prod » toujours affiché |
| 43 | `43-helm-rollback-prod-history.png` | 06-trois-environnements | `helm rollback stack-prod 1` : retour au chart 0.1.0 (révisions 4 et 5) |
| 44 | `44-helm-upgrade-dev-clusterip-port-forward.png` | 06-trois-environnements | `--set frontend.service.type=ClusterIP` sur dev + `kubectl port-forward` |
| 45 | `45-site-dev-via-port-forward.png` | 06-trois-environnements | site de dev ouvert par le port-forward (`127.0.0.1:9090`) |
| 46 | `46-keep-prod-message-apres-reinstall.png` | 06-trois-environnements | bonus `keep` : « Je suis la prod » réapparaît après `helm uninstall` + `helm install` |
| 47 | `47-helm-rollback-prod-0-3-0-history.png` | 06-trois-environnements | montée en 0.3.0 puis `helm rollback stack-prod 1` : historique |
| 48 | `48-helm-rollback-prod-message-conserve.png` | 06-trois-environnements | message de prod toujours là après le rollback |

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

---

## 04 — Déploiement de l'application d'origine (namespace `tuto`)

- **Fichier :** `04-deploiement-tutoriel-origine.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Commandes :**
  1. `kubectl config current-context` → `minikube` (vérifier qu'on est sur le cluster local)
  2. `kubectl create namespace tuto` → `namespace/tuto created`
  3. `kubectl apply -n tuto -f Project-2/k8s/tutoriel-origine/`
- **Objets créés (6) :**
  - Deployments : `frontend`, `redis-follower`, `redis-leader`
  - Services : `frontend`, `redis-follower`, `redis-leader`
- **Commentaire :** on installe les manifestes du tutoriel **sans modification**, dans un
  namespace isolé (`tuto`), pour reproduire le problème du client (perte des messages). Le
  `README.md` du dossier est ignoré par kubectl (seuls les `.yaml` sont lus). Utile pour la
  partie 2 de la doc (« Constater le problème »).

---

## 05 — État de l'application d'origine (`kubectl get all -n tuto`)

- **Fichier :** `05-etat-application-origine.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Commande :** `kubectl get all -n tuto`
- **Ce qu'on voit :**
  - **6 pods** `Running`, `READY 1/1`, 0 redémarrage : 3 `frontend`, 2 `redis-follower`, 1 `redis-leader`.
  - **3 Services** :
    - `frontend` : `LoadBalancer`, port `80:30205/TCP`, `EXTERNAL-IP <pending>` → normal tant que
      `minikube tunnel` n'est pas lancé.
    - `redis-follower` et `redis-leader` : `ClusterIP`, port `6379` → accessibles seulement
      depuis l'intérieur du cluster.
  - **3 Deployments** (3/3, 2/2, 1/1) et les **ReplicaSets** qu'ils ont créés.
- **À retenir :** chaîne de création `Deployment → ReplicaSet → Pods`. Le suffixe des noms
  (ex. `frontend-88dcd974c-b4hsx`) = identifiant du ReplicaSet + identifiant aléatoire du pod.
- **Commentaire :** l'application d'origine tourne correctement. Prochaine étape : y accéder via
  `minikube tunnel`, puis supprimer le pod `redis-leader` pour constater la perte des messages.

---

## 06 — `minikube tunnel` actif

- **Fichier :** `06-minikube-tunnel.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Commande :** `minikube tunnel` (dans un terminal dédié, laissé ouvert)
- **Ce qu'on voit :**
  - Demande du mot de passe `sudo` : nécessaire pour créer la route réseau et ouvrir le port 80.
  - `route: 10.96.0.0/12 -> 192.168.49.2` : le réseau des Services du cluster (`10.96.0.0/12`)
    est rendu joignable depuis le poste, via le nœud minikube (`192.168.49.2`).
  - `services: [frontend]` : le seul Service `LoadBalancer` détecté, celui du site web.
  - `minikube`, `router`, `loadbalancer emulator` : **no errors**.
- **Commentaire :** `minikube tunnel` simule le load balancer d'un cloud : il donne une
  `EXTERNAL-IP` aux Services `LoadBalancer` (sous Linux : l'IP du Service dans le cluster, ex.
  `10.105.199.2` ; sous macOS / Windows : `127.0.0.1`). Il doit rester
  ouvert pendant toute l'utilisation. Utile pour la partie 2 (accès à l'application) et pour
  l'environnement local des parties suivantes.

---

## 07 — Adresse externe du site (`EXTERNAL-IP`)

- **Fichier :** `07-ip-externe-frontend.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Commande :** `kubectl get svc frontend -n tuto` (avec `minikube tunnel` ouvert)
- **Ce qu'on voit :**
  - `TYPE LoadBalancer`, `CLUSTER-IP 10.105.199.2`, **`EXTERNAL-IP 10.105.199.2`**
    (avant le tunnel : `<pending>`, voir capture 05).
  - `PORT(S) 80:30205/TCP` : port 80 du Service, `30205` = port ouvert sur le nœud (NodePort,
    créé automatiquement pour un LoadBalancer).
- **Point important :** sous **Linux**, `minikube tunnel` donne au Service **sa propre IP de
  cluster** comme adresse externe, joignable grâce à la route `10.96.0.0/12 -> 192.168.49.2`
  (capture 06). Sous **macOS / Windows** (Docker Desktop), l'adresse serait `127.0.0.1`.
- **Accès :** http://10.105.199.2
- **Commentaire :** preuve que l'application d'origine est accessible depuis le poste. Utile
  pour la partie 2 de la doc et pour la section « Dépannage » (adresse différente selon l'OS).

---

## 08 — Le livre d'or avec des messages (avant le test)

- **Fichier :** `08-messages-avant-suppression.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Accès :** http://10.105.199.2 (adresse obtenue en capture 07)
- **Ce qu'on voit :** l'application Guestbook fonctionne. 3 messages ont été saisis :
  « Bonjour », « Je m'appelle », « Martin ».
- **Ce qui se passe derrière :** chaque envoi est **écrit** sur `redis-leader` ; l'affichage
  **lit** les messages sur `redis-follower`, qui a recopié le leader.
- **Commentaire :** état « avant » du test de perte de données. Prochaine action : supprimer
  le pod `redis-leader`, puis recharger la page.

---

## 09 — Suppression du pod `redis-leader`

- **Fichier :** `09-suppression-pod-leader.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Commande :** `kubectl delete pod -n tuto -l role=leader`
- **Résultat :** `pod "redis-leader-869887855b-rp4xr" deleted from tuto namespace`
- **Explication :** `-l role=leader` sélectionne le pod par son **étiquette** (label) au lieu de
  son nom complet. Le Deployment `redis-leader` détecte qu'il manque un pod et en **recrée un
  neuf** automatiquement. Cette action simule un redémarrage, une panne ou une mise à jour.

---

## 10 — Les messages ont disparu 💥

- **Fichier :** `10-messages-perdus.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-decouverte-guestbook`
- **Action :** rechargement de http://10.105.199.2 une fois le nouveau pod `redis-leader` démarré.
- **Résultat :** la page est **vide**. Les 3 messages de la capture 08 sont perdus.
- **Pourquoi :**
  1. Redis garde les messages **en mémoire uniquement** (aucun disque, aucune persistance).
  2. Le nouveau pod `redis-leader` démarre donc **vide**.
  3. Les `redis-follower` se resynchronisent sur ce nouveau leader vide et **perdent aussi**
     leurs copies.
- **Commentaire :** c'est **exactement le problème du client** (Cloud Hôtels). Captures 08 → 09
  → 10 = preuve « avant / action / après » pour la partie 2 de la doc. Corrigé en partie 4
  (disque persistant + configuration Redis).

---

## 11 — Création des fichiers de manifestes

- **Fichier :** `11-creation-fichiers-manifestes.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-manifestes-kubernetes`
- **Dossier :** `Project-2/k8s/`
- **Commande :** `touch namespaces.yaml frontend-configmap.yaml redis-follower-configmap.yaml frontend-deployment.yaml frontend-service.yaml redis-follower-deployment.yaml redis-follower-service.yaml redis-leader-deployment.yaml redis-leader-service.yaml`
- **Résultat :** 9 fichiers vides (0 octet), à côté du dossier `tutoriel-origine/`.

  | Brique | Fichiers |
  |---|---|
  | Environnements | `namespaces.yaml` |
  | frontend | `frontend-configmap.yaml`, `frontend-deployment.yaml`, `frontend-service.yaml` |
  | redis-follower | `redis-follower-configmap.yaml`, `redis-follower-deployment.yaml`, `redis-follower-service.yaml` |
  | redis-leader | `redis-leader-deployment.yaml`, `redis-leader-service.yaml` |

- **Commentaire :** un fichier par objet Kubernetes, nommé `<brique>-<type>.yaml` (même
  convention que les templates Helm de la partie 5). Les fichiers de persistance du leader
  (`redis-leader-configmap.yaml`, `redis-leader-pvc.yaml`) sont ajoutés en partie 4.

---

## 12 — Installation de nos manifestes dans `dev`

- **Fichier :** `12-apply-manifestes-dev.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-manifestes-kubernetes`
- **Commandes :**
  1. `kubectl config current-context` → `minikube`
  2. `kubectl apply -f k8s/namespaces.yaml` → `dev`, `staging`, `prod` **unchanged**
  3. `kubectl apply -n dev -f k8s/`
- **Résultat :** 2 ConfigMaps, 3 Deployments et 3 Services **created** dans `dev`.
- **À noter :**
  - `unchanged` : les namespaces existaient déjà (créés lors d'un essai précédent). `kubectl
    apply` ne refait rien quand l'objet est déjà conforme : c'est l'**idempotence**.
  - Le 2e `apply` relit `namespaces.yaml` (il est dans le dossier) : sans effet, `unchanged`.
  - Le sous-dossier `tutoriel-origine/` n'est **pas** lu (`-f` sur un dossier n'est pas récursif).

---

## 13 — État de l'application dans `dev`

- **Fichier :** `13-etat-manifestes-dev.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-manifestes-kubernetes`
- **Commande :** `kubectl get all,cm -n dev`
- **Ce qu'on voit :**
  - **5 pods** `Running`, `READY 1/1`, 0 redémarrage : 2 `frontend`, 2 `redis-follower`,
    1 `redis-leader`. `1/1` = la **readiness probe** est validée.
  - **3 Services** : `frontend` en `LoadBalancer` (`EXTERNAL-IP <pending>` tant que `minikube
    tunnel` n'est pas lancé) ; `redis-follower` et `redis-leader` en `ClusterIP`, port 6379.
  - **3 Deployments** : 2/2, 2/2, 1/1.
  - **ConfigMaps** : `frontend-config` (3 réglages), `redis-follower-config` (2 réglages).
    `kube-root-ca.crt` est créée automatiquement par Kubernetes dans chaque namespace (certificat
    du cluster), ce n'est pas la nôtre.
- **Différence avec le tutoriel (capture 05) :** 2 frontends au lieu de 3, réglages dans des
  ConfigMaps, contrôles de santé actifs.

---

## 14 — Endpoints : chaque Service trouve ses pods

- **Fichier :** `14-endpoints-dev.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-manifestes-kubernetes`
- **Commande :** `kubectl get endpoints -n dev`
- **Ce qu'on voit :**

  | Service | Endpoints (IP des pods : port) |
  |---|---|
  | `frontend` | `10.244.0.10:80`, `10.244.0.11:80` → les 2 pods du site |
  | `redis-follower` | `10.244.0.12:6379`, `10.244.0.13:6379` → les 2 copies |
  | `redis-leader` | `10.244.0.14:6379` → la base principale |

- **À retenir :** aucune ligne vide (`<none>`) → les **sélecteurs** des Services correspondent
  bien aux **étiquettes** des pods (vérification demandée par l'énoncé, K5). Le frontend ne
  pointe que vers ses pods, le leader et les copies sont bien séparés (correction du sélecteur
  commun `app: redis` du tutoriel).
- **Avertissement :** `v1 Endpoints is deprecated in v1.33+` → l'objet `Endpoints` est remplacé
  par `EndpointSlice`. Sans impact ; commande équivalente : `kubectl get endpointslices -n dev`.

---

## 15 — L'application fonctionne avec nos manifestes (`dev`)

- **Fichier :** `15-application-dev-fonctionnelle.png`
- **Date :** 2026-11-02
- **Branche :** `feat/p2-manifestes-kubernetes`
- **Accès :** `minikube tunnel` + `kubectl get svc frontend -n dev` → `http://<EXTERNAL-IP>`
- **Ce qu'on voit :** 3 messages enregistrés et affichés : « Bonjour », « Martin », « Enchanté ».
- **Ce que ça prouve :**
  - Le site **écrit** sur `redis-leader` et **lit** sur `redis-follower` grâce aux adresses de la
    ConfigMap `frontend-config` (`GET_HOSTS_FROM=env` + `REDIS_*_SERVICE_HOST`).
  - Les copies se synchronisent sur le leader grâce à la ConfigMap `redis-follower-config`.
  - Nos manifestes réécrits (étiquettes, probes, limites, ConfigMaps) fonctionnent comme le
    tutoriel.
- **Remarque :** des messages de test erronés ont été supprimés avant la capture avec
  `kubectl exec -n dev deploy/redis-leader -- redis-cli DEL guestbook` (tous les messages sont
  stockés dans une seule clé Redis, `guestbook`).
- **Limite restante :** toujours **pas de persistance** → corrigé en partie 4.

---

## 16 — Installation de la persistance dans `dev`

- **Fichier :** `16-apply-persistance-dev.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Commandes :**
  ```bash
  kubectl apply -n dev -f k8s/
  kubectl get pvc -n dev
  kubectl rollout status deploy/redis-leader -n dev
  ```
- **Ce qu'on voit :**

  | Ligne | Signification |
  |---|---|
  | `configmap/redis-leader-config created` | Nouvelle ConfigMap : le fichier `redis.conf` (`dir /data`, `appendonly yes`) |
  | `persistentvolumeclaim/redis-leader-data created` | Nouveau PVC : la demande de disque |
  | `deployment.apps/redis-leader configured` | Le leader est modifié (`Recreate`, `args`, volumes) |
  | tout le reste `unchanged` | Frontend et followers ne sont pas touchés |
  | PVC `Bound`, `1Gi`, `RWO`, `standard` | Le disque a été créé par la StorageClass **par défaut** de minikube (`standard`) et est lié au PVC |
  | `successfully rolled out` | Le nouveau pod leader (avec le disque monté sur `/data`) est prêt |

- **À retenir :** `STORAGECLASS = standard` alors qu'on n'a **pas** écrit de `storageClassName`
  dans le PVC → preuve que la classe par défaut est utilisée (exigence K7). Avec
  `storageClassName: ""`, le PVC serait resté `Pending`.

---

## 17 — Messages avant la suppression du pod leader (avec persistance)

- **Fichier :** `17-messages-avant-suppression-persistance.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Accès :** `minikube tunnel` (terminal dédié) + `kubectl get svc frontend -n dev` → `http://<EXTERNAL-IP>`
- **Ce qu'on voit :** 3 messages : « Premier test », « Apres ajout », « de la persistance ».
- **À retenir :** même départ que la capture 08 (partie 2), mais cette fois le leader a un disque.

---

## 18 — Les messages sont bien dans Redis

- **Fichier :** `18-redis-get-avant-suppression.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Commande :** `kubectl exec -n dev deploy/redis-leader -- redis-cli GET guestbook`
- **Ce qu'on voit :** `,Premier test,Apres ajout,de la persistance`
- **À retenir :** tous les messages sont dans **une seule clé** Redis, `guestbook`, séparés par
  des virgules. La virgule au début est normale : l'application ajoute `,message` à la fin de la
  valeur, qui était vide au départ.

---

## 19 — Redis écrit bien sur le disque persistant

- **Fichier :** `19-verification-config-redis.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Commandes :**
  ```bash
  kubectl exec -n dev deploy/redis-leader -- redis-cli CONFIG GET dir
  kubectl exec -n dev deploy/redis-leader -- redis-cli CONFIG GET appendonly
  kubectl exec -n dev deploy/redis-leader -- ls -l /data
  ```
- **Ce qu'on voit :**

  | Résultat | Signification |
  |---|---|
  | `dir` → `/data` | Redis écrit ses fichiers dans `/data`, là où le PVC est monté (exigence K6) |
  | `appendonly` → `yes` | Le mode AOF est actif : chaque écriture est journalisée |
  | `appendonly.aof` (209 octets) | Le journal AOF, qui contient les messages |
  | `dump.rdb` (175 octets) | Une copie complète créée par le leader quand les **followers** se sont synchronisés (la réplication passe par ce fichier) |
  | propriétaire `redis redis` | Redis tourne avec l'utilisateur `redis`, pas root (grâce à `args`) |

- **À retenir :** prouve que `redis.conf` (ConfigMap) est bien utilisé et que les données sont
  sur le disque persistant (exigence K7 : « les fichiers de données Redis dans `/data` »).

---

## 20 — Suppression du pod leader

- **Fichier :** `20-suppression-pod-leader-persistance.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Commandes :**
  ```bash
  kubectl delete pod -n dev -l app.kubernetes.io/component=redis-leader
  kubectl get pods -n dev -w      # Ctrl+C une fois le nouveau pod prêt
  ```
- **Ce qu'on voit :** le pod `redis-leader-84cb46857f-jljpl` est supprimé ; le Deployment en
  recrée un nouveau, `redis-leader-84cb46857f-8px85`, qui passe de `0/1` à `1/1 Running` en
  ~12 s (le temps que la readiness probe réussisse).
- **À retenir :** même manipulation que la capture 09 (partie 2). Le nouveau pod rebranche le
  **même PVC** sur `/data`.

---

## 21 — Les messages sont conservés ✅

- **Fichier :** `21-messages-conserves-apres-suppression.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Ce qu'on voit :** après actualisation de la page, les 3 messages sont **toujours là**.
- **À retenir :** c'est le **test de non-perte imposé** (K7) : réussi. À comparer avec la
  capture 10 (partie 2), où tous les messages avaient disparu.

---

## 22 — Le nouveau pod a relu les messages

- **Fichier :** `22-redis-get-apres-suppression.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-persistance-redis`
- **Commande :** `kubectl exec -n dev deploy/redis-leader -- redis-cli GET guestbook`
- **Ce qu'on voit :** `,Premier test,Apres ajout,de la persistance`, identique à la capture 18.
- **À retenir :** c'est un **nouveau** pod (capture 20), mais au démarrage Redis a relu le
  journal `appendonly.aof` sur le disque et retrouvé tous les messages.

---

## 23 — `Recreate` : l'ancien pod s'arrête avant le nouveau

- **Fichier :** `23-recreate-ordre-des-pods.png`
- **Date :** 2026-11-03
- **Branche :** `fix/p2-complements-persistance`
- **Commandes :**
  ```bash
  # Terminal 1 (lancé en premier) : observer uniquement le leader
  kubectl get pods -n dev -l app.kubernetes.io/component=redis-leader -w
  # Terminal 2 : déclencher une mise à jour du leader
  kubectl rollout restart deploy/redis-leader -n dev
  ```
- **Ce qu'on voit (dans l'ordre) :**

  | Ligne | Signification |
  |---|---|
  | `84cb46857f-8px85` `Running` | L'ancien pod leader |
  | `84cb46857f-8px85` `Terminating` puis `Completed` | ① L'ancien Redis **s'arrête** |
  | `9965b5457-qn5fc` `Pending` → `ContainerCreating` | ② Le nouveau pod n'apparaît **qu'ensuite** |
  | `9965b5457-qn5fc` `1/1 Running` (12 s) | ③ Le nouveau Redis est prêt |

- **À retenir :** c'est la preuve de la stratégie `Recreate` (exigence K4). En `RollingUpdate`,
  le nouveau pod serait apparu **avant** l'arrêt de l'ancien. Le début du nom change
  (`84cb46857f` → `9965b5457`) : la mise à jour a créé un nouveau ReplicaSet.
- **Remarque :** les lignes `Completed` de l'ancien pod qui réapparaissent plus bas sont la
  suppression de l'objet par Kubernetes ; son conteneur était déjà arrêté.

---

## 24 — Messages conservés après la mise à jour du leader

- **Fichier :** `24-redis-get-apres-recreate.png`
- **Date :** 2026-11-03
- **Branche :** `fix/p2-complements-persistance`
- **Commande :** `kubectl exec -n dev deploy/redis-leader -- redis-cli GET guestbook`
- **Ce qu'on voit :** `,Premier test,Apres ajout,de la persistance`
- **À retenir :** le nouveau pod (`9965b5457-qn5fc`) a rebranché le même disque et relu le
  journal AOF : aucune perte pendant une mise à jour.

---

## 25 — Redémarrage complet de minikube

- **Fichier :** `25-redemarrage-minikube-pods.png`
- **Date :** 2026-11-03
- **Branche :** `fix/p2-complements-persistance`
- **Commandes :**
  ```bash
  minikube stop && minikube start
  kubectl get pods -n dev -w      # Ctrl+C quand les 5 pods sont 1/1
  ```
- **Ce qu'on voit :**

  | Élément | Signification |
  |---|---|
  | `1 node stopped` puis `Restarting existing docker container` | Tout le cluster a été éteint puis rallumé |
  | `RESTARTS` +1 sur chaque pod (`2` pour frontend / followers, `1` pour le leader) | Tous les conteneurs ont redémarré |
  | Pods `0/1` puis `1/1` en ~30 à 70 s | Les readiness probes valident chaque pod l'un après l'autre |

- **Remarques :** `minikube 1.39.0 is available` et l'avertissement de version de `kubectl`
  (1.37.1 contre Kubernetes 1.35.1) sont sans conséquence ici.

---

## 26 — Messages conservés après le redémarrage complet

- **Fichier :** `26-redis-get-apres-redemarrage-minikube.png`
- **Date :** 2026-11-03
- **Branche :** `fix/p2-complements-persistance`
- **Commande :** `kubectl exec -n dev deploy/redis-leader -- redis-cli GET guestbook`
- **Ce qu'on voit :** `,Premier test,Apres ajout,de la persistance`
- **À retenir :** bonus de l'exigence K7 réussi : même après l'arrêt **de tout le cluster**, le
  disque persistant a été conservé et Redis a relu son journal AOF.

---

## 27 — `helm lint` du chart

- **Fichier :** `27-helm-lint-chart.png`
- **Date :** 2026-11-03
- **Branche :** `feat/p2-chart-helm`
- **Commande :** `helm lint helm/guestbook` (depuis `Project-2/`, Helm 4.3.0)
- **Ce qu'on voit :** `1 chart(s) linted, 0 chart(s) failed`.
- **À retenir :** le chart est valide (structure, `Chart.yaml`, templates rendus avec
  `values.yaml`). Exigence H1.
- **Remarque :** `[INFO] Chart.yaml: icon is recommended` est une simple suggestion (une icône
  pour un catalogue de charts), sans conséquence. Le lint avec `-f values-<ENV>.yaml` sera fait
  en partie 6, quand ces fichiers existeront.

---

## 28 — `helm lint` et `helm install` des 3 environnements

- **Fichier :** `28-helm-lint-install-environnements.png` (2 captures du terminal assemblées)
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commande :** depuis `Project-2/`, une boucle sur les 3 environnements :
  `for env in dev staging prod; do helm lint helm/guestbook -f helm/guestbook/values-$env.yaml; helm install stack-$env helm/guestbook/ --namespace $env --create-namespace -f helm/guestbook/values-$env.yaml; done`
- **Ce qu'on voit :** pour chaque environnement, `1 chart(s) linted, 0 chart(s) failed`, puis
  `STATUS: deployed`, `REVISION: 1`, `Install complete` pour `stack-dev` (namespace `dev`),
  `stack-staging` (`staging`) et `stack-prod` (`prod`), chart `guestbook-0.1.0`. Les NOTES donnent
  le port de chaque environnement : `:8080`, `:8081`, `:80`.
- **À retenir :** **une seule recette, installée 3 fois** ; seul le fichier `-f values-<ENV>.yaml`
  change. Le lint valide le chart avec les valeurs de chaque environnement (H1), et les NOTES
  confirment que la surcharge du port a bien été prise en compte.
- **Remarque :** un premier essai avait échoué (`cluster unreachable … no route to host`) car
  minikube était arrêté : `kubectl config current-context` dit **quel** cluster est visé, pas s'il
  est allumé → `minikube start` / `minikube status` d'abord.

---

## 29 — `helm list -A` : les 3 releases

- **Fichier :** `29-helm-list-trois-releases.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commande :** `helm list -A` (`-A` = tous les namespaces)
- **Ce qu'on voit :** 3 releases, chacune dans son namespace : `stack-dev` → `dev`,
  `stack-staging` → `staging`, `stack-prod` → `prod`. Toutes en `REVISION 1`, `STATUS deployed`,
  `CHART guestbook-0.1.0`, `APP VERSION v5`.
- **À retenir :** le **même** chart (`guestbook-0.1.0`) est installé 3 fois, séparément. Chaque
  release a son propre historique (révision 1 = première installation) : on pourra mettre à jour
  ou revenir en arrière sur un environnement sans toucher aux autres.
- **Remarque :** `CHART` = version de la recette (`version` du `Chart.yaml`) ; `APP VERSION` =
  version de l'application (`appVersion`, ici le tag `v5` de l'image du frontend).

---

## 30 — Contenu du namespace `prod`

- **Fichier :** `30-kubectl-get-all-prod.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get all,cm,pvc -n prod`
- **Ce qu'on voit :**
  - **Pods** : 3 `frontend`, 2 `redis-follower`, 1 `redis-leader`, tous `1/1 Running`, 0 redémarrage.
  - **Services** : `frontend` en `LoadBalancer` sur le **port 80** (`EXTERNAL-IP <pending>` : pas
    encore de `minikube tunnel`) ; `redis-leader` et `redis-follower` en `ClusterIP` sur 6379.
  - **Deployments** : `frontend 3/3`, `redis-follower 2/2`, `redis-leader 1/1`.
  - **ConfigMaps** : `frontend` (3 clés : `GET_HOSTS_FROM` + les 2 adresses Redis),
    `redis-follower` (2), `redis-leader` (1 : `redis.conf`). `kube-root-ca.crt` est créé par
    Kubernetes dans chaque namespace (âge 37h = création du namespace).
  - **PVC** : `stack-prod-guestbook-redis-leader-data`, `Bound`, **5Gi**, `RWO`, StorageClass
    `standard` (celle par défaut de minikube).
- **À retenir :** les surcharges de `values-prod.yaml` sont bien appliquées (3 frontends,
  2 followers, disque de 5Gi, port 80). Tous les noms commencent par `stack-prod-guestbook-` :
  préfixe de la release, donc aucun conflit avec dev ou staging.

---

## 31 — Contenu du namespace `dev` (après nettoyage)

- **Fichier :** `31-kubectl-get-all-dev.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get all,cm,pvc -n dev`
- **Ce qu'on voit :**
  - **Pods** : 1 `frontend`, 1 `redis-follower`, 1 `redis-leader`, tous `1/1 Running`.
  - **Services** : `frontend` en `LoadBalancer` sur le **port 8080** (`EXTERNAL-IP <pending>` :
    pas encore de `minikube tunnel`) ; Redis en `ClusterIP` sur 6379.
  - **ConfigMaps** : les 3 du chart + `kube-root-ca.crt` (créé par Kubernetes).
  - **PVC** : `stack-dev-guestbook-redis-leader-data`, `Bound`, **1Gi**, `RWO`, `standard`.
- **À retenir :** il ne reste **que** la release Helm `stack-dev`. L'ancienne application des
  étapes 3-4 (objets sans préfixe : `frontend`, `redis-leader`…, installés par `kubectl apply -f
  k8s/`) a été supprimée avant, avec `kubectl delete -n dev -f` sur chaque fichier de `k8s/` sauf
  `namespaces.yaml`, puis le PV resté `Released`. Dev garde les valeurs par défaut sauf le port
  (8080) et le label `environment`.

---

## 32 — Contenu du namespace `staging`

- **Fichier :** `32-kubectl-get-all-staging.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get all,cm,pvc -n staging`
- **Ce qu'on voit :**
  - **Pods** : 2 `frontend`, 1 `redis-follower`, 1 `redis-leader`, tous `1/1 Running`.
  - **Services** : `frontend` en `LoadBalancer` sur le **port 8081** ; Redis en `ClusterIP` sur 6379.
  - **Deployments** : `frontend 2/2`, `redis-follower 1/1`, `redis-leader 1/1`.
  - **PVC** : `stack-staging-guestbook-redis-leader-data`, `Bound`, **1Gi**, `RWO`, `standard`.
- **À retenir :** surcharges de `values-staging.yaml` appliquées : 2 frontends (pour pouvoir
  tester une mise à jour sans coupure) et port 8081. Avec les captures 30 (prod) et 31 (dev) :
  **même chart, 3 tailles différentes** (frontends 1 / 2 / 3, disque 1Gi / 1Gi / 5Gi, ports
  8080 / 8081 / 80).

---

## 33 — `minikube tunnel` et les adresses des 3 environnements

- **Fichier :** `33-minikube-tunnel-ip-trois-environnements.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commandes :** en bas, `minikube tunnel` (terminal dédié, laissé ouvert, demande le mot de
  passe `sudo`) ; en haut, `kubectl get svc -A | grep frontend`.
- **Ce qu'on voit :**
  - **Tunnel** : `minikube: Running`, route `10.96.0.0/12 -> 192.168.49.2`, et les 3 Services
    servis : `stack-dev-…`, `stack-prod-…`, `stack-staging-guestbook-frontend` ; aucune erreur.
  - **Adresses** (colonne `EXTERNAL-IP`, plus de `<pending>`) :

    | Env | EXTERNAL-IP | Port | URL |
    |---|---|---|---|
    | dev | `10.110.15.78` | 8080 | `http://10.110.15.78:8080` |
    | staging | `10.106.111.203` | 8081 | `http://10.106.111.203:8081` |
    | prod | `10.96.10.135` | 80 | `http://10.96.10.135` |
- **À retenir :** le tunnel joue le rôle du « fournisseur de LoadBalancer » qu'aurait un cloud. Il
  ajoute sur le PC une route vers le réseau des Services (`10.96.0.0/12`) via la machine minikube
  (`192.168.49.2`). **Sous Linux**, chaque Service reçoit **sa propre IP** (ici égale à sa
  `CLUSTER-IP`) ; sous macOS / Windows ce serait `127.0.0.1` pour les 3, d'où des ports différents
  imposés par l'énoncé. Adresse du site = `EXTERNAL-IP` + **premier** port de `PORT(S)` (le
  second, `31225`…, est le NodePort interne).

---

## 34 — Modification d'une valeur de staging

- **Fichier :** `34-values-staging-replicas-3.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Action :** dans l'éditeur, `helm/guestbook/values-staging.yaml`, ligne 7 :
  `frontend.replicaCount` passe de `2` à **`3`**.
- **Ce qu'on voit :** le fichier de staging ne contient que ses surcharges (`environment`, `team`,
  `replicaCount`, `port: 8081`). Aucun template n'est modifié.
- **À retenir :** c'est la vérification de l'exigence H3 (`enonce/HELM.md`) : on change **une
  valeur** dans le fichier de l'environnement, puis `helm upgrade` (capture 35). Valeur remise
  ensuite par `helm rollback` ou en remettant `2`.

---

## 35 — `helm upgrade` de staging : 3 frontends

- **Fichier :** `35-helm-upgrade-staging-replicas.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commandes :** `helm upgrade stack-staging helm/guestbook -n staging -f helm/guestbook/values-staging.yaml`
  puis `kubectl get deploy -n staging`.
- **Ce qu'on voit :** `has been upgraded`, `STATUS: deployed`, **`REVISION: 3`**, `Upgrade complete`.
  Le Deployment frontend affiche `2/3 READY`, `3 UP-TO-DATE` : le 3ᵉ pod vient d'être créé et
  démarre (readiness probe). Vérifié juste après : `3/3`, nouveau pod de 36 s à côté des deux
  anciens (34 min), leader et follower **non touchés**.
- **À retenir :**
  - Helm compare l'ancien et le nouveau résultat et n'applique **que la différence** : seul le
    nombre de pods du frontend change, aucun pod existant n'est recréé.
  - Révision 2 = upgrade précédent **sans changement** (valeurs identiques à la révision 1,
    vérifié avec `helm get values --revision`) → idempotence : rien n'a bougé dans le cluster.
  - Historique (`helm history stack-staging -n staging`) : 1 `Install complete`, 2 et 3
    `Upgrade complete`, la 3 est `deployed`, les autres `superseded`.

---

## 36 à 39 — Test d'idempotence en `prod`

**But :** montrer qu'un `helm upgrade` **sans aucun changement** (mêmes valeurs, même chart) ne
touche à rien dans le cluster. Les 4 captures se lisent dans l'ordre.

### 36 — Pods de `prod` avant l'upgrade

- **Fichier :** `36-idempotence-prod-pods-avant.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get pods -n prod`
- **Ce qu'on voit :** 3 frontends `…-55fc467fb8-…` (37m), 2 followers `…-5db7bc565b-…` (37m),
  1 leader `…-784fdc6b4d-m4qrk` (11m : recréé lors du test de persistance). Tous `Running`,
  0 redémarrage.

### 37 — `helm upgrade` sans changement

- **Fichier :** `37-idempotence-prod-helm-upgrade.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `helm upgrade stack-prod helm/guestbook/ -n prod -f helm/guestbook/values-prod.yaml`
- **Ce qu'on voit :** `has been upgraded`, `STATUS: deployed`, **`REVISION: 2`**,
  `Upgrade complete`, chart `guestbook-0.1.0` (inchangé).

### 38 — Pods de `prod` après l'upgrade

- **Fichier :** `38-idempotence-prod-pods-apres.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get pods -n prod`
- **Ce qu'on voit :** **exactement les mêmes pods** que sur la capture 36 : mêmes noms (même
  suffixe de ReplicaSet `55fc467fb8` / `5db7bc565b` / `784fdc6b4d`, mêmes suffixes de pod), âges
  qui continuent (37m → 43m, 11m → 16m), 0 redémarrage.

### 39 — Historique de la release

- **Fichier :** `39-idempotence-prod-helm-history.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `helm history stack-prod -n prod`
- **Ce qu'on voit :** révision 1 `superseded` / `Install complete`, révision 2 `deployed` /
  `Upgrade complete`, même chart `guestbook-0.1.0`, même `APP VERSION v5`.

**À retenir (36 → 39) :** Helm a bien enregistré une **nouvelle révision** (trace de l'action
dans l'historique), mais comme le YAML produit est identique, Kubernetes n'a **rien** modifié :
aucun pod recréé, aucun redémarrage. Relancer la même commande est donc **sans danger** :
c'est l'idempotence.

---

## 40 à 42 — Mise à jour de la version du chart en `prod`

**But :** vérifier qu'une **vraie** mise à jour (nouvelle version du chart) remplace les pods
**sans coupure** et **sans perte de messages**. Action préalable : dans `Chart.yaml`,
`version: 0.1.0` → **`0.2.0`**, puis
`helm upgrade stack-prod helm/guestbook/ -n prod -f helm/guestbook/values-prod.yaml`.

### 40 — Remplacement des pods (`kubectl get pods -n prod -w`)

- **Fichier :** `40-upgrade-version-prod-rolling-update.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `kubectl get pods -n prod -w` (lancée pendant l'upgrade)
- **Ce qu'on voit :**
  - **Nouveaux ReplicaSets** (nouveau hash) pour les 3 composants : frontend `55fc467fb8` →
    `79d5658bc9`, follower `5db7bc565b` → `758fb5fb67`, leader `784fdc6b4d` → `978ff4875`.
    Cause : le label `helm.sh/chart: guestbook-<version>` est dans le gabarit des pods → il
    change → Kubernetes considère que c'est une nouvelle version des pods.
  - **Frontend et follower = RollingUpdate** : un nouveau pod passe `0/1` → `1/1` (~12 s,
    readiness probe) **avant** qu'un ancien passe `Terminating`. Le cycle se répète pour chaque
    pod → toujours des pods prêts, **pas de coupure**.
  - **Leader = Recreate** : l'ancien leader (`m4qrk`) n'apparaît déjà plus au début de la liste ;
    il a été arrêté **avant** la création du nouveau (`978ff4875-gjvz6`), car le disque
    `ReadWriteOnce` ne se branche qu'à un seul Redis.
  - **Anciens frontends → `Completed`** : Apache est le processus n°1 du conteneur, il reçoit
    l'ordre d'arrêt (SIGTERM) et sort proprement (code 0).
  - **Anciens followers → `Error`** : dans l'image Google, le processus n°1 est
    `/bin/sh -c /run.sh`, qui lance `redis-server`. Le SIGTERM arrive à `sh`, qui l'ignore (un
    processus n°1 ignore les signaux qu'il ne traite pas) et ne le transmet pas à Redis →
    au bout du délai de grâce (30 s) Kubernetes force l'arrêt (SIGKILL, code 137) → `Error`.
    **Sans conséquence** : le follower n'a pas de données propres et son remplaçant était déjà
    prêt.

### 41 — Historique : révision 3 en `guestbook-0.2.0`

- **Fichier :** `41-upgrade-version-prod-helm-history.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commande :** `helm history stack-prod -n prod`
- **Ce qu'on voit :** 1 `Install complete` (0.1.0), 2 `Upgrade complete` (0.1.0, test
  d'idempotence, captures 36-39), **3 `deployed` / `Upgrade complete` avec `guestbook-0.2.0`**.
  `APP VERSION` reste `v5` : on a changé la version de la **recette**, pas celle de l'application.

### 42 — Le message de prod est toujours là

- **Fichier :** `42-upgrade-version-prod-message-conserve.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Action :** ouvrir `http://10.96.10.135` (prod) après l'upgrade.
- **Ce qu'on voit :** « Voici la prod » est toujours affiché.
- **À retenir (40 → 42) :** tous les pods ont été remplacés, y compris le Redis leader, mais le
  message a survécu : il est sur le **PVC**, que l'upgrade ne touche pas. Le nouveau leader a
  remonté le même disque et relu son journal AOF.

---

## 43 — `helm rollback` de `prod` vers la révision 1

- **Fichier :** `43-helm-rollback-prod-history.png`
- **Date :** 2026-11-04
- **Branche :** `feat/p2-environnements-helm`
- **Commandes :** `helm rollback stack-prod 1 -n prod` puis `helm history stack-prod -n prod`
- **Ce qu'on voit :** `Rollback was a success!`. Historique : 1 `Install complete` (0.1.0),
  2 `Upgrade complete` (0.1.0), 3 `Upgrade complete` (**0.2.0**), **4 `Rollback to 1` (0.1.0)**,
  **5 `Rollback to 1` (0.1.0, `deployed`)**.
- **À retenir :**
  - Un rollback **ne supprime pas** de révision : il en **ajoute** une nouvelle (4), copie de la
    révision visée (1). Le chart actif redevient `guestbook-0.1.0`.
  - La révision 5 vient d'un **second rollback lancé par erreur** (13:48:51, 10 s après le
    premier). Il est sans effet : même contenu que la 4, donc Kubernetes ne change rien
    (idempotence). Helm n'a pas de commande pour retirer une ligne de l'historique : c'est un
    **journal**, on ne réécrit pas le passé. Ne pas supprimer le Secret
    `sh.helm.release.v1.stack-prod.v5` à la main (casse l'historique).
  - L'historique de cette release a été perdu ensuite (`helm uninstall` lors du test `keep`) : le
    test complet montée de version → rollback → message conservé a été refait : captures 47-48.

---

## 44 et 45 — Passage du frontend de `dev` en ClusterIP (test par port-forward)

**But :** simuler la phase de test du cloud (étape 8) : le site n'est **pas** exposé (Service
interne `ClusterIP`), on y accède uniquement depuis son poste par un tunnel `kubectl port-forward`.
La surcharge se fait par `--set` sur la ligne de commande, **sans** fichier de valeurs en plus.

### 44 — `helm upgrade … --set frontend.service.type=ClusterIP` puis port-forward

- **Fichier :** `44-helm-upgrade-dev-clusterip-port-forward.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commandes :**
  `helm upgrade stack-dev helm/guestbook -n dev -f helm/guestbook/values-dev.yaml --set frontend.service.type=ClusterIP`
  puis `kubectl port-forward svc/stack-dev-guestbook-frontend 9090:8080 -n dev`
- **Ce qu'on voit :**
  - `REVISION: 2`, `Upgrade complete`, chart `guestbook-0.2.0` (version montée en partie 6).
  - Les **NOTES changent toutes seules** avec le type de Service : « type ClusterIP », « Le
    Service est interne : ouvrir un tunnel depuis le poste », commande `kubectl port-forward`
    proposée (le `if` du `NOTES.txt`).
  - Port-forward : `Forwarding from 127.0.0.1:9090 -> 80`, puis `Handling connection for 9090`
    (le navigateur est passé par le tunnel).
- **À retenir :** `9090:8080` = port **local** 9090 → port **du Service** 8080 (port de dev) ;
  kubectl affiche `-> 80` car il va directement au port du **conteneur** (Apache écoute sur 80).
  Le port local est libre : 9090 a été choisi ici, les NOTES proposent 8080.
  **Priorité des valeurs :** `--set` > `-f values-dev.yaml` > `values.yaml`.

### 45 — Le site de `dev` par le tunnel

- **Fichier :** `45-site-dev-via-port-forward.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Action :** ouvrir `http://127.0.0.1:9090`.
- **Ce qu'on voit :** le livre d'or de **dev** : « Voici la prod » (saisi par erreur dans l'onglet
  de dev lors du test d'isolation) puis « Voici le dev » ×2.
- **À retenir :** le site marche alors que le Service n'a **plus d'adresse externe** : seul le poste
  qui a lancé le port-forward y accède. Retour en `LoadBalancer` : relancer `helm upgrade` **sans**
  le `--set` (Helm repart des fichiers de valeurs).

---

## 46 — Bonus `keep` : le message de `prod` survit à `helm uninstall`

- **Fichier :** `46-keep-prod-message-apres-reinstall.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Déroulé :**
  1. 1ᵉʳ essai **raté** : `helm uninstall stack-prod -n prod` puis `kubectl get pvc -n prod` →
     `No resources found` : le PVC (et les messages) ont été supprimés. Cause : `keep: true` était
     dans `values-prod.yaml` mais **aucun template ne lisait la valeur**.
  2. Correction dans `templates/redis-leader-pvc.yaml` : si `redisLeader.persistence.keep` vaut
     `true`, annotation `helm.sh/resource-policy: keep` sur le PVC.
  3. 2ᵉ essai : `helm upgrade` (pose l'annotation) → message « Je suis la prod » →
     `helm uninstall stack-prod -n prod` → le PVC **reste** → `helm install stack-prod helm/guestbook
     -n prod -f helm/guestbook/values-prod.yaml` (14:04:45).
- **Ce qu'on voit :** `http://10.111.107.233` (nouvelle IP : le Service a été recréé) affiche
  « Je suis la prod ».
- **Vérifié sur le cluster :** le PVC `stack-prod-guestbook-redis-leader-data` a été créé à
  13:53:37, **avant** la release (14:04:45), et porte `helm.sh/resource-policy: keep`.
- **À retenir :** avec l'annotation, Helm **ne supprime pas** le PVC à l'uninstall. À la
  réinstallation, le PVC portant le même nom est **réutilisé**. Sans l'annotation (dev), le PVC est
  supprimé et, la StorageClass `standard` étant en `reclaimPolicy: Delete`, le disque aussi. Pour
  vraiment effacer les données de prod : `kubectl delete pvc stack-prod-guestbook-redis-leader-data -n prod`.

---

## 47 et 48 — Montée de version puis rollback en `prod`, message conservé

### 47 — Historique : 0.2.0 → 0.3.0 → rollback

- **Fichier :** `47-helm-rollback-prod-0-3-0-history.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Commandes :** (`Chart.yaml` : `version: 0.3.0`, puis `helm upgrade stack-prod helm/guestbook -n
  prod -f helm/guestbook/values-prod.yaml`, lancé **depuis `Project-2/`**) ;
  `helm history stack-prod -n prod` ; `helm rollback stack-prod 1 -n prod` ; `helm history …`.
- **Ce qu'on voit :** avant : 1 `Install complete` (0.2.0), 2 `Upgrade complete` (**0.3.0**,
  `deployed`). Après : `Rollback was a success!` et une **révision 3** `Rollback to 1`
  (**0.2.0**, `deployed`).
- **Vérifié sur le cluster :** le PVC est toujours celui de 13:53:37, annotation `keep` présente :
  ni l'upgrade ni le rollback ne l'ont recréé.
- **Piège rencontré :** lancée depuis `Project/` au lieu de `Project-2/`, la commande échoue avec
  `Error: repo helm not found` : le dossier `helm/guestbook` n'existant pas, Helm lit
  `helm/guestbook` comme « chart `guestbook` du dépôt `helm` ».

### 48 — Le message est toujours là après le rollback

- **Fichier :** `48-helm-rollback-prod-message-conserve.png`
- **Date :** 2026-11-04 · **Branche :** `feat/p2-environnements-helm`
- **Action :** recharger `http://10.111.107.233` après le rollback.
- **Ce qu'on voit :** « Je suis la prod ».
- **À retenir (47 → 48) :** exigence H6 « montée de version en direct, puis retour à la révision
  précédente ; les messages saisis restent visibles à chaque étape » ✅. Un rollback **ajoute**
  une révision (copie de la révision visée) et ne touche pas au disque.

