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

