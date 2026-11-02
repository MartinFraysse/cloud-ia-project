# Projet d'équipe — « Livre d'or Cloud » : GKE + Terraform + Helm sur Google Cloud

**Équipe :** 5 étudiantes / étudiants
**Prérequis :** modules Cloud (fondamentaux GCP), Kubernetes (découverte, avancé), Helm,
Terraform (fondamentaux + atelier)
**Outils :** Git, VS Code, Terraform, kubectl, Helm, minikube, Docker Desktop, gcloud
(+ plugin `gke-gcloud-auth-plugin`), Google Cloud (GKE Autopilot)
**Livrables :** un dépôt Git + une documentation de transfert de connaissance (README et/ou
slides) + une soutenance avec démonstration

> Cet énoncé est découpé en plusieurs fichiers. Celui-ci décrit le contexte, l'organisation, les
> livrables et l'évaluation. Les exigences techniques détaillées sont dans :
>
> | Fichier | Contenu |
> |---|---|
> | [`TERRAFORM.md`](TERRAFORM.md) | Provisionnement du cluster GKE Autopilot avec Terraform (module, variables, providers, outputs, idempotence, connexion au cluster) |
> | [`KUBERNETES.md`](KUBERNETES.md) | Objets Kubernetes attendus (namespaces, deployments, probes, ressources, stratégie, services, ConfigMaps, volumes persistants) |
> | [`HELM.md`](HELM.md) | Packaging de l'application en chart Helm (structure, templates, `_helpers.tpl`, fichiers `values-<ENV>.yaml`, releases, installation et mise à jour) |
>
> Chaque exigence y est décrite sous la forme **Attendu / Vérification** : ce que vous devez
> produire, et comment l'examinateur le contrôlera.

---

## 1. Contexte

**Cloud Hôtels** (entreprise fictive) est un groupe hôtelier d'une quarantaine d'établissements.
La direction marketing souhaite proposer à ses clients un **livre d'or numérique** : à la fin de
leur séjour, les clients laissent un message depuis une borne ou leur téléphone, et les messages
s'affichent en direct dans le hall de l'hôtel.

Un prototype existe : c'est l'application open source **Guestbook** (un frontend PHP et une base
Redis en mode leader / followers), publiée en exemple par le projet Kubernetes. Le prototype a été
installé à la main sur un poste de développeur, et lors de la démonstration au comité de
direction, **un redémarrage a effacé tous les messages saisis**. La DSI lance donc le projet
**« Livre d'or Cloud »**, confié à votre équipe — l'**équipe Plateforme** — avec les attentes
suivantes :

- l'application tourne sur un **cluster Kubernetes managé** dans Google Cloud (GKE), lui-même
  créé **en code** avec Terraform et reconstructible à l'identique à tout moment ;
- **les messages des clients persistent** : un redémarrage de pod, une mise à jour de
  l'application ou le remplacement d'un nœud ne doivent faire perdre aucun message ;
- l'application est **packagée avec Helm** et déployée dans **trois environnements isolés**
  (`dev`, `staging`, `prod`) à partir du **même chart** : seules les valeurs changent d'un
  environnement à l'autre ;
- les développeurs peuvent travailler **en local** (minikube + Docker Desktop) avec le même chart
  que celui utilisé sur le cloud ;
- toute la configuration de l'application est **externalisée** (ConfigMaps, fichiers de valeurs) :
  aucune valeur d'environnement n'est figée dans les manifestes ;
- l'installation et les montées de version se font **uniquement avec des commandes Helm**, sans
  `kubectl apply` manuel sur les environnements partagés.

À la fin du projet, la plateforme sera **reprise en exploitation (run) par une société de conseil
externe**. C'est le rôle que joue l'examinateur : un consultant qui découvre votre travail et doit
être capable, **avec votre seule documentation**, de recréer le cluster, de redéployer
l'application, de l'exploiter et de la faire évoluer. Votre documentation est donc un livrable à
part entière, au même titre que le code.

## 2. Ce que vous devez construire

### 2.1 Vue d'ensemble

```
                      ┌────────────────────────────────────────────────────┐
                      │               Dépôt Git de l'équipe                │
                      │   terraform/     k8s/     helm/guestbook/   docs/  │
                      └──────────┬─────────────────────┬───────────────────┘
                                 │                     │
         ENVIRONNEMENT CLOUD     │                     │      ENVIRONNEMENT LOCAL
 ┌───────────────────────────────▼──────┐   ┌──────────▼──────────────────────────────┐
 │ Terraform ──▶ module GKE             │   │ minikube (driver Docker Desktop)        │
 │   beta-autopilot-public-cluster      │   │                                         │
 │   = cluster « autopilot-cluster-1 »  │   │                                         │
 │                                      │   │                                         │
 │ gcloud get-credentials ──▶ kubectl   │   │ kubectl (contexte minikube)             │
 │                                      │   │                                         │
 │ helm install/upgrade                 │   │ helm install/upgrade                    │
 │   ns dev      ─ release stack-dev    │   │   ns dev      ─ release stack-dev       │
 │   ns staging  ─ release stack-staging│   │   ns staging  ─ release stack-staging   │
 │   ns prod     ─ release stack-prod   │   │   ns prod     ─ release stack-prod      │
 │                                      │   │                                         │
 │ Accès : ClusterIP + port-forward     │   │ Accès : LoadBalancer + minikube tunnel  │
 │   puis LoadBalancer (IP publique)    │   │                                         │
 └──────────────────┬───────────────────┘   └──────────────────┬──────────────────────┘
                    │                                          │
                    └────────── MÊME chart Helm ───────────────┘
                                MÊMES templates
                     seuls les fichiers values-<ENV>.yaml
                       (et le type de Service) diffèrent
```

Principe directeur : **Terraform crée le cluster, Helm y déploie l'application.** Terraform ne
déploie aucun objet applicatif dans le cluster ; Helm ne crée aucune ressource GCP.

### 2.2 L'application Guestbook

L'application à déployer est l'exemple officiel Kubernetes :

- tutoriel : [Example: Deploying PHP Guestbook application with Redis](https://kubernetes.io/docs/tutorials/stateless-application/guestbook/) ;
- code source des images : [GoogleCloudPlatform/kubernetes-engine-samples — quickstarts/guestbook](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/main/quickstarts/guestbook).

Elle est composée de trois briques :

| Brique | Rôle | Image de référence (tutoriel) |
|---|---|---|
| `redis-leader` | Base Redis principale, reçoit les écritures | `docker.io/redis:6.0.5` |
| `redis-follower` | Réplicas Redis en lecture, synchronisés sur le leader | `us-docker.pkg.dev/google-samples/containers/gke/gb-redis-follower:v2` |
| `frontend` | Interface web PHP : lit sur les followers, écrit sur le leader | `us-docker.pkg.dev/google-samples/containers/gke/gb-frontend:v5` |

Telle que fournie par le tutoriel, l'application **ne persiste pas ses données** : c'est le
problème rencontré par Cloud Hôtels. À vous de la rendre persistante (voir
[`KUBERNETES.md`](KUBERNETES.md), section Persistance).

> **À étudier avant de commencer :** le frontend et les followers retrouvent le leader par son
> **nom de Service**. Lisez le code source des images (variable `GET_HOSTS_FROM`, scripts de
> démarrage) pour comprendre comment ces noms sont résolus. Cela conditionne la manière dont vous
> pourrez templatiser les noms de Services dans le chart Helm.

### 2.3 Démarche attendue

Le projet se construit en trois étapes, qui correspondent à trois dossiers du dépôt :

1. **`k8s/` — manifestes Kubernetes « bruts »** : vous réécrivez et enrichissez les manifestes du
   tutoriel (probes, ressources, stratégie, ConfigMaps, persistance…) et vous les validez sur
   minikube avec `kubectl apply`. Ce dossier sert de référence lisible et de base au chart.
2. **`helm/guestbook/` — chart Helm** : vous transformez ces manifestes en templates Helm et vous
   déployez les trois environnements avec des releases Helm, d'abord en local, puis sur GKE.
3. **`terraform/` — cluster GKE** : vous provisionnez le cluster GKE Autopilot avec le module
   Terraform imposé, puis vous vous y connectez avec `kubectl` pour y installer le chart.

Les étapes 1 et 3 peuvent être menées en parallèle par des membres différents de l'équipe.

## 3. Les environnements

### 3.1 Environnement local — minikube + Docker Desktop

- Docker Desktop installé et démarré ; minikube lancé avec le driver Docker
  (`minikube start --driver=docker`).
- Les trois namespaces `dev`, `staging`, `prod` et les trois releases `stack-dev`,
  `stack-staging`, `stack-prod` sont déployés sur le cluster minikube, **avec le même chart** que
  sur le cloud.
- Le frontend est exposé par un Service de type **`LoadBalancer`**, rendu accessible depuis le
  poste par la commande **`minikube tunnel`** (à laisser tourner dans un terminal dédié).
- La persistance s'appuie sur la StorageClass par défaut de minikube.

> **À anticiper :** avec le driver Docker, `minikube tunnel` publie les Services `LoadBalancer`
> sur `127.0.0.1`. Trois Services exposés sur le même port entreraient en conflit : prévoyez un
> port de Service différent par environnement (c'est précisément l'une des valeurs à templatiser).

### 3.2 Environnement cloud — lab Google Skills

L'environnement cloud est un **projet GCP temporaire** fourni par le lab Google Skills suivant :

- https://www.skills.google/paths/11/course_templates/2/labs/619578

Contraintes à anticiper, typiques d'un environnement de lab :

- **durée limitée** : le projet et tout ce qu'il contient sont supprimés à la fin de la session.
  La création d'un cluster Autopilot prend à elle seule une dizaine de minutes ; relevez la durée
  affichée dans le panneau du lab et vérifiez que votre déploiement complet (Terraform + Helm)
  tient **largement** dans ce temps ;
- **identifiants changeants** : `project_id`, région, compte et identifiants sont différents à
  chaque session. Les valeurs de `project_id` et `region` à utiliser sont **celles fournies par le
  lab** ; elles sont passées en variables, jamais écrites dans le code ;

Sur le cloud, l'accès au frontend se fait **en deux temps** :

1. **Test** : Service de type `ClusterIP` + `kubectl port-forward` → l'application est vérifiée
   sans être exposée sur Internet ;
2. **Ouverture** : une fois le test validé, `helm upgrade` bascule le Service en type
   `LoadBalancer` → GKE provisionne une IP publique.

Conséquence directe, et c'est tout l'intérêt de l'IaC : vous allez **reconstruire votre
environnement de zéro à chaque session**. Si cela demande plus que quelques commandes
documentées, votre automatisation n'est pas terminée.

## 4. Consignes transverses

- **Idempotence partout** : `terraform plan` après `apply` → `No changes` ; relancer
  `helm upgrade` avec les mêmes valeurs ne modifie aucun objet Kubernetes (même spec, aucun pod
  recréé).
- **Code commenté** : chaque fichier (`.tf`, manifeste, template, fichier de valeurs) commence par
  un commentaire qui explique son rôle ; les choix non évidents sont expliqués là où ils sont
  faits. Dans les fichiers `values*.yaml`, chaque valeur est commentée.
- **Un seul chart, plusieurs environnements** : aucune copie du chart par environnement. Les
  différences passent exclusivement par les fichiers `values-<ENV>.yaml` (et, pour la différence
  local / cloud, par une surcharge documentée — voir [`HELM.md`](HELM.md)).
- **Pas d'image `latest`** : toutes les images sont référencées avec un tag explicite.
- **Rien de sensible dans Git** : state Terraform, dossier `.terraform/`, `terraform.tfvars`
  réel, fichiers `kubeconfig`, identifiants GCP → `.gitignore` dès le premier commit.
- **Travail en équipe visible** : historique Git avec des commits réguliers et explicites de
  **chacun des 5 membres** (branches et merge requests / pull requests recommandées).

## 5. Structure de dépôt attendue

La structure exacte est libre, mais elle doit rester proche de celle-ci et être expliquée dans le
README de l'équipe :

```
livre-or-cloud/
├── README.md                       → documentation de transfert (point d'entrée unique)
├── docs/                           → schémas, décisions techniques, runbooks, slides éventuels
├── terraform/
│   ├── versions.tf                 → required_version + required_providers (versions épinglées)
│   ├── variables.tf                → variables (type, description, default si optionnel)
│   ├── main.tf                     → appel du module GKE beta-autopilot-public-cluster
│   ├── outputs.tf                  → nom du cluster, région, endpoint, commande de connexion…
│   ├── terraform.tfvars.example    → modèle versionné ; le vrai terraform.tfvars ne l'est pas
│   └── README.md                   → (optionnel) détail ressources / variables / providers / outputs
├── k8s/                            → manifestes bruts validés sur minikube (étape 1)
│   ├── namespaces.yaml
│   ├── redis-leader-configmap.yaml
│   ├── redis-leader-pvc.yaml
│   ├── redis-leader-deployment.yaml
│   ├── redis-leader-service.yaml
│   ├── redis-follower-deployment.yaml
│   ├── redis-follower-service.yaml
│   ├── frontend-configmap.yaml
│   ├── frontend-deployment.yaml
│   └── frontend-service.yaml
└── helm/
    └── guestbook/                  → chart Helm (arborescence standard)
        ├── Chart.yaml
        ├── .helmignore
        ├── values.yaml             → valeurs par défaut, toutes commentées
        ├── values-dev.yaml
        ├── values-staging.yaml
        ├── values-prod.yaml
        ├── charts/
        └── templates/
            ├── _helpers.tpl        → noms et labels communs
            ├── NOTES.txt
            └── … un template par objet Kubernetes
```

## 6. Organisation de l'équipe

Votre équipe est composé de 5 membres.
Vous pouvez vous organiser comme vous le souhaitez pour réaliser ce projet.

La documentation est **l'affaire de tous** : chacun documente ce qu'il produit, le tech lead
assure la cohérence d'ensemble.

Pendant la soutenance, **n'importe quel membre** peut être interrogé sur **n'importe quelle
partie** du projet. Organisez des points réguliers pour que chacun comprenne le travail des
autres.

### Jalons conseillés

1. **Cadrage** : répartition des rôles, dépôt Git initialisé avec sa structure et son
   `.gitignore`, étude du code source de Guestbook, première session de lab pour relever les
   contraintes de l'environnement cloud.
2. **Manifestes fonctionnels en local** : `kubectl apply -f k8s/` déploie Guestbook sur minikube,
   persistance démontrée (suppression du pod leader sans perte de messages).
3. **Chart Helm fonctionnel en local** : `stack-dev`, `stack-staging` et `stack-prod` tournent sur
   minikube, accessibles via `minikube tunnel`.
4. **Cloud fonctionnel** : `terraform apply` crée le cluster, connexion `kubectl`, les trois
   releases sont installées sur GKE, test par `port-forward` puis ouverture par `LoadBalancer`.
5. **Transfert** : documentation finalisée, puis **répétition générale** : un membre de l'équipe
   recrée tout de zéro dans une nouvelle session de lab en suivant uniquement le README.

## 7. Documentation de transfert de connaissance

Rédigez votre documentation (README, éventuellement complété par `docs/` ou par des slides) pour
**un consultant qui reprend le run** : il connaît Terraform, Kubernetes, Helm et GCP, mais ne
connaît **ni votre projet, ni vos choix, ni vos conventions**. Il n'aura personne à qui poser de
questions.

**Critère de réussite :** le consultant doit pouvoir, en suivant uniquement votre documentation,
recréer le cluster dans un projet GCP vierge, redéployer les trois environnements (et
l'environnement local), puis réaliser les opérations courantes ci-dessous.

La documentation doit couvrir :

1. **Présentation** : objectif de la plateforme, périmètre, ce qui est automatisé et ce qui ne
   l'est pas.
2. **Architecture** : schéma des deux environnements, des trois namespaces et des objets
   Kubernetes de chaque release ; flux entre frontend, leader et followers ; où sont stockées les
   données ; frontière entre Terraform et Helm.
3. **Prérequis et accès** : outils et versions, comptes et droits nécessaires, installation du
   plugin `gke-gcloud-auth-plugin`, contraintes de l'environnement de lab.
4. **Déploiement de zéro** : procédure pas à pas, commandes copiables, résultat attendu à chaque
   étape, pour l'environnement local **et** pour le cloud.
5. **Runbooks d'exploitation** — pour chacun : quand l'utiliser, commandes, comment vérifier que
   l'opération a réussi :
   - déployer une nouvelle version de l'application (`helm upgrade`) ;
   - revenir à la révision précédente d'une release (`helm history` / `helm rollback`) ;
   - modifier la configuration d'un environnement (fichier `values-<ENV>.yaml`) ;
   - augmenter le nombre de réplicas ou les ressources d'un composant ;
   - augmenter la taille du volume persistant (et ses limites) ;
   - vérifier que les données sont bien persistées et où elles se trouvent ;
   - passer le frontend de `ClusterIP` à `LoadBalancer` (et inversement) ;
   - se reconnecter au cluster depuis un nouveau poste ;
   - désinstaller une release, puis détruire le cluster proprement.
6. **Référence** : ressources et module Terraform, variables, providers et outputs ; objets
   Kubernetes créés par le chart ; tableau des valeurs Helm (nom, description, valeur par défaut,
   valeur par environnement).
7. **Décisions techniques** : chaque choix structurant avec sa justification et les alternatives
   écartées (stratégie `Recreate`, mode de persistance Redis, valeurs des probes et des
   ressources, nommage des Services, surcharge local / cloud, gestion du state Terraform…).
8. **Où regarder en cas de problème** : commandes de diagnostic (`kubectl describe`,
   `kubectl logs`, `kubectl get events`, `helm status`, `helm get values`…), erreurs déjà
   rencontrées et leur solution.
9. **Limites connues et dette technique** : ce qui n'est pas terminé, ce qui n'est pas prêt pour
   la production (haute disponibilité de Redis, sauvegardes, HTTPS…), ce que vous feriez ensuite.

## 8. Soutenance et passation

**Format :** 30-45 minutes par équipe — environ 10-15 minutes de présentation, 15 minutes de
démonstration, 10 à 15 minutes de questions.

La présentation se fait comme une **réunion de passation** au consultant qui reprend le run :
pas de cours sur Kubernetes ou Helm, mais *votre* plateforme, *vos* choix et *comment
l'exploiter*.

**Scénario de démonstration imposé** (sur une session de lab neuve ; le `terraform apply` peut
être lancé avant la soutenance compte tenu de la durée de création du cluster) :

1. `terraform plan` → `No changes` ; `terraform output` affiche le nom et la région du cluster.
2. Connexion au cluster : plugin `gke-gcloud-auth-plugin`, `gcloud container clusters
   get-credentials`, puis `kubectl cluster-info`.
3. `helm install stack-dev` dans le namespace `dev` avec un Service `ClusterIP`,
   `kubectl port-forward`, ajout de messages dans le livre d'or.
4. `helm upgrade stack-dev` → le Service passe en `LoadBalancer`, l'application est accessible
   par son IP publique.
5. Installation de `stack-staging` et `stack-prod` ; `helm list -A` montre les trois releases
   dans leurs namespaces.
6. **Test de persistance** : suppression du pod `redis-leader` de `prod` → le pod est recréé, les
   messages sont toujours là.
7. Montée de version d'une release (`helm upgrade` avec une nouvelle version de chart) →
   `helm history` montre la nouvelle révision, les messages sont toujours là.
8. `kubectl describe` d'un deployment : l'examinateur vérifie probes, requests / limits, labels
   et stratégie `Recreate` du leader.
9. Démonstration rapide de l'environnement local : minikube, `minikube tunnel`, même chart,
   même résultat.
10. `helm uninstall` des releases puis `terraform destroy`.

L'examinateur peut aussi demander à un membre de l'équipe, choisi au hasard, de dérouler un
runbook de la documentation en direct.

## 9. Évaluation

- Terraform (fichiers `versions.tf`, `variables.tf`, `terraform.tfvars`, `outputs.tf`, module GKE conforme, variabilisation, idempotence) — voir [`TERRAFORM.md`](TERRAFORM.md)
- Connexion au cluster et environnement cloud (plugin, credentials, séquence ClusterIP → port-forward → LoadBalancer)
- Kubernetes — deployments (probes, requests / limits, stratégie `Recreate`), services, namespaces, ConfigMaps — voir [`KUBERNETES.md`](KUBERNETES.md)
- Persistance des données (PVC sur `/data`, StorageClass par défaut, configuration Redis, non-perte démontrée)
- Helm — structure du chart, templates, `_helpers.tpl`, valeurs templatisées — voir [`HELM.md`](HELM.md)
- Helm — environnements et releases (`values-<ENV>.yaml`, namespaces, `stack-<ENV>`, install / upgrade)
- Environnement local minikube (même chart, `minikube tunnel`, parité avec le cloud)
- Documentation de transfert de connaissance (complétude, exactitude, runbooks, décisions)
- Soutenance et démonstration (clarté, maîtrise individuelle, respect du scénario)

## 10. Définition de « terminé »

Avant la soutenance, vérifiez que vous pouvez cocher chaque ligne :

- [ ] Une session de lab neuve + le README suffisent à tout recréer, sans aide orale.
- [ ] `terraform plan` après `apply` → `No changes`.
- [ ] `versions.tf`, `variables.tf`, `terraform.tfvars(.example)` et `outputs.tf` existent et sont
      correctement renseignés ; le cluster est créé **uniquement** avec le module
      `beta-autopilot-public-cluster` et les arguments imposés.
- [ ] Le README documente les ressources, variables, providers et outputs Terraform.
- [ ] Chaque deployment a ses readiness / liveness probes et ses requests / limits ; le
      deployment `redis-leader` utilise la stratégie `Recreate`.
- [ ] Toute la configuration de l'application est portée par des ConfigMaps.
- [ ] Les données Redis sont stockées sur un volume persistant monté sur `/data`, provisionné par
      la StorageClass par défaut du cluster ; supprimer le pod leader ne fait perdre aucun
      message.
- [ ] Le chart respecte l'arborescence standard, passe `helm lint`, et ses labels communs sont
      générés par `_helpers.tpl`.
- [ ] Les trois releases `stack-dev`, `stack-staging`, `stack-prod` tournent dans les namespaces
      `dev`, `staging`, `prod`, en local **et** sur GKE, avec le **même** chart.
- [ ] Installation et montées de version réalisées uniquement avec `helm install` /
      `helm upgrade`.
- [ ] Accès local par `LoadBalancer` + `minikube tunnel` ; accès cloud par `ClusterIP` +
      `port-forward`, puis `LoadBalancer`.
- [ ] Aucun identifiant ni state dans le dépôt ni dans son historique.
- [ ] Chaque membre de l'équipe sait expliquer et exécuter chaque runbook.

## 11. Ressources

- Kubernetes — [Example: Deploying PHP Guestbook application with Redis](https://kubernetes.io/docs/tutorials/stateless-application/guestbook/)
- GitHub — [kubernetes-engine-samples / quickstarts / guestbook](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/main/quickstarts/guestbook)
- Terraform Registry — [module `beta-autopilot-public-cluster`](https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google/latest/submodules/beta-autopilot-public-cluster)
- Google Cloud — [Installer les plug-ins requis / stocker les informations du cluster pour kubectl](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)
- Helm — [Chart Template Guide](https://helm.sh/docs/chart_template_guide/) et [Best Practices](https://helm.sh/docs/chart_best_practices/)
- minikube — [Accessing apps : LoadBalancer access / `minikube tunnel`](https://minikube.sigs.k8s.io/docs/handbook/accessing/)
- Lab Google Skills (environnement cloud) — https://www.skills.google/paths/11/course_templates/2/labs/619578
