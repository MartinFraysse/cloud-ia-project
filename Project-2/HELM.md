# Exigences Helm — Packaging et déploiement de Guestbook

> Fichier rattaché à l'énoncé principal : [`README.md`](README.md).
> Chaque mécanisme ci-dessous est **obligatoire**. Pour chacun : ce qui est attendu (**Attendu**),
> et comment l'examinateur le vérifiera (**Vérification**).
>
> Les objets générés par le chart doivent respecter les règles de
> [`exigences-kubernetes.md`](exigences-kubernetes.md).

## Objectif

Les manifestes du dossier `k8s/` sont réécrits en **templates Helm** pour former un chart
`guestbook` unique, installé trois fois — une **release par environnement**, chacune dans son
**namespace** :

| Namespace | Release | Fichier de valeurs |
|---|---|---|
| `dev` | `stack-dev` | `values-dev.yaml` |
| `staging` | `stack-staging` | `values-staging.yaml` |
| `prod` | `stack-prod` | `values-prod.yaml` |

---

## H1. Structure — arborescence standard du chart

**Attendu :** le chart respecte l'arborescence standard Helm (celle produite par
`helm create`, nettoyée de ce qui ne sert pas) :

```
helm/guestbook/
├── Chart.yaml            → apiVersion v2, name, description, type, version, appVersion
├── .helmignore           → fichiers exclus du package
├── values.yaml           → valeurs par défaut, TOUTES commentées
├── values-dev.yaml       → surcharges de l'environnement dev
├── values-staging.yaml   → surcharges de l'environnement staging
├── values-prod.yaml      → surcharges de l'environnement prod
├── charts/               → dépendances (vide si aucune)
└── templates/
    ├── _helpers.tpl      → noms et labels communs
    ├── NOTES.txt         → message affiché après install / upgrade
    ├── frontend-configmap.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── redis-leader-configmap.yaml
    ├── redis-leader-pvc.yaml
    ├── redis-leader-deployment.yaml
    ├── redis-leader-service.yaml
    ├── redis-follower-deployment.yaml
    └── redis-follower-service.yaml
```

- `Chart.yaml` : `apiVersion: v2`, `type: application`, une `version` de chart en SemVer
  (incrémentée à chaque modification du chart) et une `appVersion` (version de l'application
  déployée) ;
- un fichier de template par objet Kubernetes, nommé `<brique>-<type>.yaml` ;
- les fichiers inutiles générés par `helm create` (HPA, ServiceAccount, Ingress, tests…) sont
  supprimés s'ils ne sont pas utilisés ;
- `NOTES.txt` affiche, selon le type de Service, la commande pour accéder à l'application
  (`minikube tunnel`, `kubectl port-forward …` ou `kubectl get svc … -w`).

**Vérification :** `helm lint helm/guestbook -f helm/guestbook/values-<ENV>.yaml` passe sans
erreur pour les trois environnements ; `helm package helm/guestbook` produit
`guestbook-<version>.tgz`.

## H2. Templates — aucune valeur d'environnement en dur

**Attendu :**

- chaque manifeste de `k8s/` a son équivalent dans `templates/` ; toute valeur susceptible de
  varier provient de `.Values`, de `.Release` ou de `.Chart` ;
- le namespace n'est jamais écrit en dur : il est fourni par `helm install -n <ENV>` (et, si vous
  l'écrivez dans `metadata`, via `{{ .Release.Namespace }}`) ;
- les noms des objets sont construits à partir de fonctions de `_helpers.tpl` (voir H4) ;
- les templates exploitent réellement le moteur : `include` + `nindent`, `toYaml` (blocs
  `resources`, probes), `quote`, `default`, conditions `if` (type de Service, StorageClass),
  boucles `range` (variables d'environnement de la ConfigMap) ;
- chaque template commence par un commentaire Helm (`{{/* ... */}}`) décrivant l'objet généré.

**Vérification :**

```bash
helm template stack-dev helm/guestbook -n dev -f helm/guestbook/values-dev.yaml
```

produit des manifestes valides ; `grep -rn "dev\|staging\|prod" helm/guestbook/templates/` ne
trouve aucune valeur d'environnement codée en dur.

## H3. Valeurs templatisées — `values.yaml` et `values-<ENV>.yaml`

**Attendu :** les valeurs suivantes sont **obligatoirement** templatisées. Leur valeur par défaut
est dans `values.yaml` ; ce qui change d'un environnement à l'autre est surchargé dans
`values-<ENV>.yaml` :

| Valeur | Objets concernés | Exemple de clé |
|---|---|---|
| Nombre de **replicas** des deployments | 3 deployments | `frontend.replicaCount` |
| **Labels** des ressources Kubernetes | tous les objets (via `_helpers.tpl`) | `commonLabels.environment`, `commonLabels.team` |
| **Images** des conteneurs (dépôt, tag, politique de pull) | 3 deployments | `frontend.image.repository`, `frontend.image.tag` |
| **Variables d'environnement** | ConfigMap frontend → deployment frontend | `frontend.env.GET_HOSTS_FROM` |
| Valeurs **cpu** et **memory** des **requests** et **limits** | 3 deployments | `frontend.resources.requests.cpu` |
| **Noms** et **ports** des Services | 3 Services (+ références dans la ConfigMap frontend) | `frontend.service.name`, `frontend.service.port` |
| **Taille** du volume persistant et **access mode** | PVC du leader | `redisLeader.persistence.size`, `redisLeader.persistence.accessMode` |
| **StorageClass** (vide par défaut) | PVC du leader | `redisLeader.persistence.storageClass: ""` |

Exigences complémentaires :

- **chaque clé** de `values.yaml` est **commentée** (rôle, unités, valeurs possibles) ;
- les fichiers `values-<ENV>.yaml` ne contiennent **que les surcharges** utiles à
  l'environnement (pas de copie intégrale de `values.yaml`) ;
- les différences entre environnements sont **réalistes et justifiées**, par exemple :

  | Paramètre | dev | staging | prod |
  |---|---|---|---|
  | `frontend.replicaCount` | 1 | 2 | 3 |
  | `redisFollower.replicaCount` | 1 | 1 | 2 |
  | Ressources | réduites | proches de prod | dimensionnées |
  | `redisLeader.persistence.size` | 1Gi | 1Gi | 5Gi |
  | `frontend.service.port` | 8080 | 8081 | 80 |
  | `commonLabels.environment` | dev | staging | prod |

- **StorageClass vide = classe par défaut du cluster :** quand
  `redisLeader.persistence.storageClass` vaut `""`, le template **n'écrit pas** le champ
  `storageClassName` (un `storageClassName: ""` littéral désactiverait le provisionnement
  dynamique — voir [`exigences-kubernetes.md`](exigences-kubernetes.md), K7) ;

**Vérification :** l'examinateur modifie une valeur dans `values-staging.yaml` (par exemple le
nombre de réplicas du frontend), lance `helm upgrade stack-staging …` et constate le changement,
sans avoir touché à un template.

## H4. Labels — générés par `_helpers.tpl`

**Attendu :**

- `templates/_helpers.tpl` définit au minimum les templates nommés suivants (le préfixe
  `guestbook.` évite les collisions avec d'éventuels sous-charts) :

  | Template nommé | Rôle |
  |---|---|
  | `guestbook.name` | nom du chart (surchargeable par `nameOverride`) |
  | `guestbook.fullname` | nom complet des objets, dérivé de la release (surchargeable par `fullnameOverride`), tronqué à 63 caractères |
  | `guestbook.chart` | `<nom>-<version>` du chart, pour le label `helm.sh/chart` |
  | `guestbook.labels` | **labels communs** à tous les objets : `helm.sh/chart`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`, `app.kubernetes.io/part-of`, + les `commonLabels` du fichier de valeurs |
  | `guestbook.selectorLabels` | labels **stables** utilisés dans les sélecteurs (`app.kubernetes.io/name`, `app.kubernetes.io/instance`) |

- le label de **composant** (`app.kubernetes.io/component: frontend | redis-leader |
  redis-follower`) est ajouté proprement à chaque objet (paramètre passé au template, ou
  template dédié par composant) ;
- **aucun label n'est écrit à la main** dans les templates d'objets : tous proviennent de
  `include "guestbook.labels"` / `include "guestbook.selectorLabels"` ;
- les sélecteurs (`spec.selector.matchLabels` des deployments, `spec.selector` des Services)
  n'incluent **ni** `app.kubernetes.io/version` **ni** `helm.sh/chart` — expliquez pourquoi
  (immutabilité du sélecteur d'un deployment, échec du `helm upgrade` sinon).

**Vérification :** `grep -rn "app.kubernetes.io" helm/guestbook/templates/*.yaml` ne remonte
aucun label écrit en dur ; `kubectl get all -n prod --show-labels` montre des labels homogènes,
dont `app.kubernetes.io/instance=stack-prod`.

## H5. Namespaces et releases — une release par environnement

**Attendu :**

- trois releases, une par namespace, avec **exactement** ces noms :
  `stack-dev` → `dev`, `stack-staging` → `staging`, `stack-prod` → `prod` ;
- les namespaces sont créés à l'installation (`--create-namespace`) ou au préalable, et ce choix
  est documenté ;
- la même procédure fonctionne sur minikube et sur GKE ; **avant toute commande Helm**, la
  documentation impose de vérifier le contexte `kubectl` courant ;
- **différence local / cloud** : le type du Service frontend (`LoadBalancer` en local,
  `ClusterIP` puis `LoadBalancer` sur GKE) est une valeur du chart. Choisissez et documentez le
  mécanisme de surcharge : second fichier de valeurs (par exemple `-f values-gke.yaml`) ou option
  `--set frontend.service.type=ClusterIP` pour la phase de test.

**Vérification :** `helm list -A` affiche les trois releases dans leurs namespaces respectifs, au
statut `deployed`.

## H6. Installation et montée de version — uniquement avec Helm

**Attendu :** l'installation et les évolutions de l'application se font **exclusivement** avec
les commandes Helm (pas de `kubectl apply` / `kubectl edit` sur les objets du chart). La
documentation fournit les commandes complètes, par exemple :

```bash
# Contrôles préalables
kubectl config current-context
helm lint helm/guestbook -f helm/guestbook/values-dev.yaml

# Installation (cloud, phase de test : ClusterIP)
helm install stack-dev helm/guestbook \
  --namespace dev --create-namespace \
  -f helm/guestbook/values-dev.yaml \
  --set frontend.service.type=ClusterIP
kubectl port-forward svc/<service-frontend> 8080:<port> -n dev

# Montée de version / changement de configuration (ouverture : LoadBalancer)
helm upgrade stack-dev helm/guestbook \
  --namespace dev \
  -f helm/guestbook/values-dev.yaml

# Suivi
helm status stack-dev -n dev
helm history stack-dev -n dev
helm get values stack-dev -n dev
```

Exigences complémentaires :

- une **montée de version** est démontrée : incrément de `version` (et le cas échéant
  d'`appVersion`) dans `Chart.yaml` et/ou changement de tag d'image, puis `helm upgrade` →
  `helm history` montre la nouvelle révision ;
- un **retour arrière** est documenté et testé : `helm rollback <release> <révision> -n <ENV>` ;
- **idempotence** : relancer `helm upgrade` avec exactement les mêmes valeurs ne recrée aucun pod
  (bonus : démonstration avec `helm diff` ou `kubectl diff`) ;
- les **données persistent** lors d'un `helm upgrade` et d'un `helm rollback` (le PVC n'est pas
  recréé) ;
- la documentation précise ce que devient le PVC lors d'un `helm uninstall` (bonus : annotation
  `helm.sh/resource-policy: keep` sur le PVC de `prod`, et procédure pour le réutiliser).

**Vérification :** l'examinateur demande une montée de version en direct, puis un retour à la
révision précédente ; les messages saisis restent visibles à chaque étape.

## H7. Lisibilité du chart

**Attendu :**

- indentation YAML correcte dans les manifestes générés (`nindent` utilisé à bon escient,
  `helm template` lisible) ;
- pas de logique complexe dupliquée : ce qui est répété plusieurs fois devient un template nommé
  dans `_helpers.tpl` ;
- les commentaires de `values.yaml` suffisent à comprendre chaque paramètre sans lire les
  templates ;

**Vérification :** un consultant peut modifier un paramètre d'environnement en ne lisant que
`values.yaml` et le fichier `values-<ENV>.yaml` concerné.

---

## Récapitulatif des contrôles

```bash
# Qualité du chart
helm lint helm/guestbook -f helm/guestbook/values-prod.yaml
helm template stack-prod helm/guestbook -n prod -f helm/guestbook/values-prod.yaml

# Releases et environnements
helm list -A
helm get values stack-prod -n prod
helm history stack-prod -n prod

# Labels générés
kubectl get all,cm,pvc -n prod --show-labels
```
