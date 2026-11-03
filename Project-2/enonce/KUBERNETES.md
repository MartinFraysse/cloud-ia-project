# Exigences Kubernetes — Objets de l'application Guestbook

> Fichier rattaché à l'énoncé principal : [`README.md`](README.md).
> Chaque mécanisme ci-dessous est **obligatoire**. Pour chacun : ce qui est attendu (**Attendu**),
> et comment l'examinateur le vérifiera (**Vérification**).
>
> Ces exigences s'appliquent d'abord aux manifestes bruts du dossier `k8s/` (validés sur
> minikube), puis au chart Helm qui en est dérivé (voir [`exigences-helm.md`](exigences-helm.md)) :
> les objets générés par le chart doivent respecter **les mêmes règles**.

## Objets attendus par environnement

Chaque environnement (`dev`, `staging`, `prod`) contient **au minimum** les objets suivants :

| Brique | Deployment | Service | ConfigMap | PersistentVolumeClaim |
|---|---|---|---|---|
| `redis-leader` | ✅ stratégie `Recreate`, 1 réplica | ✅ `ClusterIP` | ✅ configuration Redis | ✅ monté sur `/data` |
| `redis-follower` | ✅ | ✅ `ClusterIP` | (selon vos choix) | — |
| `frontend` | ✅ | ✅ `LoadBalancer` ou `ClusterIP` selon l'environnement | ✅ variables d'environnement | — |

```
                       namespace <ENV>
 ┌──────────────────────────────────────────────────────────────────┐
 │                                                                  │
 │  Service frontend ──▶ Deployment frontend (PHP)                  │
 │  (LB ou ClusterIP)        │ envFrom: ConfigMap frontend          │
 │                           │                                      │
 │            écritures ─────┤───── lectures                        │
 │                ▼                     ▼                           │
 │  Service redis-leader      Service redis-follower                │
 │        │                           │                             │
 │  Deployment redis-leader ◀── réplication ── Deployment           │
 │  (Recreate, 1 réplica)                       redis-follower      │
 │        │  ConfigMap redis (redis.conf)                           │
 │        ▼                                                         │
 │  PVC ──▶ PV (StorageClass par défaut du cluster) monté sur /data │
 └──────────────────────────────────────────────────────────────────┘
```

---

## K1. Namespaces — `dev`, `staging`, `prod`

**Attendu :**

- l'application est déployée dans **trois namespaces** : `dev`, `staging`, `prod` ;
- chaque namespace contient une instance **complète et indépendante** de l'application (frontend,
  leader, followers, ConfigMaps, volume) : les messages saisis en `dev` n'apparaissent pas en
  `prod` ;
- les manifestes ne contiennent **pas de namespace codé en dur** dans `metadata.namespace` (le
  namespace est donné à l'installation : `kubectl apply -n <ENV>` ou `helm install -n <ENV>`) ;
- bonus : chaque namespace porte un label `environment: <ENV>`.

**Vérification :** `kubectl get all,cm,pvc -n dev` (puis `staging`, `prod`) montre une instance
complète par namespace ; un message ajouté dans `dev` n'apparaît pas dans `prod`.

## K2. Deployments — readiness et liveness probes

**Attendu :**

- **chaque** conteneur de **chaque** deployment définit une `readinessProbe` **et** une
  `livenessProbe` ;
- les probes sont adaptées à la brique :

  | Brique | Probe suggérée | À justifier |
  |---|---|---|
  | `frontend` | `httpGet` sur `/` (port nommé `http`) | délais et seuils |
  | `redis-leader` / `redis-follower` | `exec` : `redis-cli ping`, ou `tcpSocket` sur 6379 | pourquoi l'une plutôt que l'autre |

- les paramètres (`initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`)
  sont choisis et **justifiés** dans la documentation, en expliquant la différence de rôle entre
  readiness (recevoir du trafic) et liveness (redémarrer le conteneur) ;
- les ports des conteneurs sont **nommés** (`http`, `redis`) et les probes y font référence par
  leur nom.

**Vérification :** `kubectl describe deploy <nom> -n <ENV>` affiche les deux probes pour chaque
conteneur ; lors d'un redémarrage, le pod n'apparaît `READY 1/1` qu'une fois la readiness probe
validée.

## K3. Deployments — requests et limits

**Attendu :**

- **chaque** conteneur définit `resources.requests` **et** `resources.limits` pour `cpu` et
  `memory` ;
- les valeurs sont **cohérentes avec la brique** et justifiées (à titre indicatif, le tutoriel
  utilise `100m` / `100Mi` en requests) ;
- les valeurs diffèrent selon l'environnement dans le chart Helm (voir
  [`exigences-helm.md`](exigences-helm.md)) — par exemple plus modestes en `dev`.

**Vérification :** `kubectl describe pod` affiche requests et limits pour chaque conteneur.

## K4. Stratégie de déploiement — `Recreate` pour `redis-leader`

**Attendu :**

- le deployment `redis-leader` déclare explicitement `strategy.type: Recreate` ;
- les deployments `frontend` et `redis-follower` restent en `RollingUpdate` (bonus : paramètres
  `maxSurge` / `maxUnavailable` choisis et justifiés) ;
- la documentation explique **pourquoi** `Recreate` est nécessaire pour le leader. Pistes à
  traiter : volume en mode d'accès `ReadWriteOnce`, un seul processus Redis qui doit écrire dans
  `/data` à un instant donné, ce qui se passerait avec un `RollingUpdate` (ancien et nouveau pod
  simultanés, volume déjà attaché à un autre nœud), et l'impact sur la disponibilité pendant la
  mise à jour.

**Vérification :** `kubectl get deploy redis-leader -n prod -o jsonpath='{.spec.strategy.type}'`
renvoie `Recreate` ; lors d'un `helm upgrade` qui modifie le leader, l'ancien pod est arrêté
**avant** que le nouveau ne démarre.

## K5. Services — exposition interne et externe

**Attendu :**

- `redis-leader` et `redis-follower` sont exposés par des Services de type **`ClusterIP`**
  (jamais exposés hors du cluster) ;
- le frontend est exposé selon l'environnement et la phase :

  | Contexte | Type de Service | Accès |
  |---|---|---|
  | **Local** (minikube) | `LoadBalancer` | `minikube tunnel` dans un terminal dédié, puis `kubectl get svc -n <ENV>` pour l'`EXTERNAL-IP` |
  | **Cloud — phase de test** | `ClusterIP` | `kubectl port-forward svc/<frontend> <port-local>:<port-service> -n <ENV>` (dans Cloud Shell : *Web Preview* sur le port local) |
  | **Cloud — après validation** | `LoadBalancer` | IP publique provisionnée par GKE (`kubectl get svc -n <ENV> -w`) |

- les **sélecteurs** des Services correspondent exactement aux labels des pods visés (vérifiez
  qu'un Service n'a pas d'`Endpoints` vides) ;
- les **noms des Services Redis** sont cohérents avec la façon dont le frontend et les followers
  retrouvent le leader (variable `GET_HOSTS_FROM`, scripts de démarrage des images) : étudiez le
  code source et documentez votre choix ;
- avec minikube, les Services `LoadBalancer` des trois environnements utilisent des **ports
  différents** pour éviter les conflits sur `127.0.0.1`.

**Vérification :** `kubectl get svc,endpoints -n <ENV>` montre des Endpoints non vides ; en local
l'application répond via `minikube tunnel` ; sur GKE elle répond via `port-forward`, puis via
l'IP publique après `helm upgrade`.

## K6. ConfigMaps — configuration externalisée

**Attendu :**

- **aucune** valeur de configuration n'est écrite directement dans la spec des conteneurs : les
  variables d'environnement et fichiers de configuration sont déclarés dans des **ConfigMaps** ;
- au minimum :
  - une ConfigMap **frontend** portant les variables d'environnement de l'application
    (`GET_HOSTS_FROM`, et le cas échéant les noms d'hôtes Redis), injectée par `envFrom` ou
    `valueFrom.configMapKeyRef` ;
  - une ConfigMap **Redis** portant un fichier `redis.conf` monté dans le conteneur du leader
    (volume de type `configMap`), et une commande de démarrage qui utilise ce fichier ;
- le contenu de `redis.conf` sert la persistance (voir K7) : au minimum le répertoire de données
  (`dir /data`) et le mode de persistance choisi, commentés ;
- aucune donnée sensible dans une ConfigMap (bonus : si vous ajoutez un mot de passe Redis, il va
  dans un **Secret**).

**Vérification :** `kubectl get cm -n <ENV>` liste les ConfigMaps ; `kubectl exec` dans le
frontend affiche les variables attendues (`env | grep GET_HOSTS_FROM`) ; dans le leader,
`redis-cli CONFIG GET dir` renvoie `/data`.

## K7. Persistance — volume persistant sur `/data`

C'est l'exigence principale du client : **aucun message ne doit être perdu**.

**Attendu :**

- un **PersistentVolumeClaim** est créé pour le leader et monté dans son conteneur sur le chemin
  **`/data`** ;
- le PVC définit sa **taille** (`resources.requests.storage`) et son **mode d'accès**
  (`accessModes`, par exemple `ReadWriteOnce`) — deux valeurs templatisées dans le chart ;
- le volume est **provisionné dynamiquement par la StorageClass par défaut du cluster**.
  Dans le chart, la valeur `storageClass` est **vide** (`""`) pour
  utiliser cette valeur par défaut ;

  > **Piège classique :** dans un manifeste Kubernetes, écrire littéralement
  > `storageClassName: ""` ne signifie **pas** « StorageClass par défaut » mais « **aucune**
  > StorageClass » (liaison statique uniquement, le PVC reste `Pending`). Pour utiliser la classe
  > par défaut, le champ `storageClassName` doit être **absent**. Votre template doit donc
  > **omettre** le champ lorsque la valeur `storageClass` est vide, et ne l'écrire que lorsqu'une
  > classe est explicitement fournie. Expliquez ce mécanisme dans votre documentation.

**Vérification — test de non-perte imposé :**

1. ajouter trois messages dans le livre d'or de l'environnement `prod` ;
2. supprimer le pod leader : `kubectl delete pod -l <label du leader> -n prod` ;
3. attendre que le nouveau pod soit `READY` (et que les followers se soient resynchronisés) ;
4. recharger la page : **les trois messages sont toujours présents** ;
5. bonus : même test après un `helm upgrade` qui modifie le leader, et après un redémarrage
   complet de minikube (`minikube stop` / `minikube start`).

`kubectl get pvc -n prod` affiche le PVC à l'état `Bound` avec la StorageClass par défaut ;
`kubectl exec` dans le leader montre les fichiers de données Redis dans `/data`.

## K8. Labels, images et bonnes pratiques

**Attendu :**

- tous les objets portent des labels cohérents, au minimum les labels recommandés
  `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/component`
  (`frontend`, `redis-leader`, `redis-follower`), `app.kubernetes.io/part-of` ; dans le chart Helm
  ils sont générés par `_helpers.tpl` ;
- les **sélecteurs** de deployments et de Services n'utilisent que des labels **stables** (pas de
  numéro de version : le sélecteur d'un deployment est immuable) ;
- toutes les images ont un tag explicite (pas de `latest`) et une `imagePullPolicy` cohérente ;
- chaque manifeste commence par un commentaire décrivant l'objet et son rôle ; les choix non
  évidents sont commentés.

**Vérification :** `kubectl get pods -n <ENV> --show-labels` montre des labels homogènes ;
`kubectl get pods -l app.kubernetes.io/component=frontend -n <ENV>` sélectionne exactement les
pods du frontend.

---

## Récapitulatif des contrôles

```bash
# Objets d'un environnement
kubectl get all,cm,pvc -n prod

# Probes, ressources, stratégie
kubectl describe deploy redis-leader -n prod
kubectl get deploy redis-leader -n prod -o jsonpath='{.spec.strategy.type}'

# Services et endpoints
kubectl get svc,endpoints -n prod

# Persistance
kubectl get storageclass
kubectl get pvc -n prod
kubectl exec -n prod deploy/redis-leader -- redis-cli CONFIG GET dir
kubectl exec -n prod deploy/redis-leader -- ls -l /data
```

(Adaptez les noms d'objets à ceux générés par votre chart.)
