# Exigences Terraform — Provisionnement du cluster GKE Autopilot

> Fichier rattaché à l'énoncé principal : [`README.md`](README.md).
> Chaque mécanisme ci-dessous est **obligatoire**. Pour chacun : ce qui est attendu (**Attendu**),
> et comment l'examinateur le vérifiera (**Vérification**).

## Objectif

Le code Terraform du dossier `terraform/` crée **un cluster GKE Autopilot** dans le projet GCP
temporaire fourni par le lab Google Skills. Il ne crée rien d'autre dans le cluster : le
déploiement applicatif est entièrement pris en charge par Helm.

```
terraform/
├── versions.tf                 → required_version + required_providers
├── variables.tf                → toutes les variables (type + description)
├── main.tf                     → appel du module GKE
├── outputs.tf                  → sorties utiles à l'exploitation
├── terraform.tfvars.example    → modèle de valeurs d'entrée (versionné)
└── terraform.tfvars            → valeurs réelles de la session de lab (NON versionné)
```

---

## T1. Module GKE imposé — `beta-autopilot-public-cluster`

**Attendu :**

- le cluster est instancié **uniquement** au moyen du module public
  [`terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster`](https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google/latest/submodules/beta-autopilot-public-cluster) :
  pas de ressource `google_container_cluster` écrite à la main ;
- le bloc `module` utilise **exclusivement** les arguments suivants, et aucun autre :

  | Argument | Valeur attendue | Commentaire |
  |---|---|---|
  | `source` | `"terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster"` | Sous-module Autopilot à cluster public |
  | `version` | `"~> 46.0"` | Version du module épinglée |
  | `project_id` | ID du projet **fourni par le lab** | Change à chaque session |
  | `name` | `"autopilot-cluster-1"` | Nom du cluster |
  | `region` | Région **fournie par le lab** | Autopilot = cluster régional |
  | `network` | `"default"` | Réseau VPC par défaut du projet de lab |
  | `subnetwork` | `"default"` | Sous-réseau par défaut de la région |
  | `ip_range_pods` | `null` | Plages secondaires gérées automatiquement par GKE |
  | `ip_range_services` | `null` | Idem |
  | `release_channel` | `"REGULAR"` | Canal de mise à jour de GKE |
  | `deletion_protection` | `false` | Indispensable pour pouvoir faire `terraform destroy` en fin de lab |

- `source` et `version` sont les seules valeurs littérales du bloc (Terraform ne permet pas de les
  variabiliser) ; **tous les autres arguments reçoivent une variable** (voir T2) ;
- chaque argument est commenté dans `main.tf` (à quoi il sert, pourquoi cette valeur).

**Vérification :** l'examinateur compare le bloc `module` à la liste ci-dessus : aucun argument
manquant, aucun argument supplémentaire ; `terraform init` télécharge le module dans la version
`46.x`.

## T2. Variables — tous les arguments variabilisés, déclarés dans `variables.tf`

**Attendu :**

- aucune valeur codée en dur dans les arguments du module (hors `source` et `version`) :
  `project_id`, `name`, `region`, `network`, `subnetwork`, `ip_range_pods`, `ip_range_services`,
  `release_channel`, `deletion_protection` passent par une variable ;
- toutes les variables sont déclarées dans le fichier **`variables.tf`** et nulle part ailleurs
  (pas de bloc `variable` dans `main.tf` ou dans `versions.tf`) ;
- chaque variable renseigne un **`type`** et un champ **`description`** explicite (à quoi elle
  sert, format attendu, exemple) ;
- un `default` n'est fourni que pour les valeurs réellement stables (`network`, `release_channel`,
  `ip_range_pods = null`…) ; **pas de `default` pour `project_id` ni pour `region`**, qui changent
  à chaque session de lab ;
- bonus : blocs `validation` pertinents (par exemple `release_channel` limité à `RAPID`,
  `REGULAR`, `STABLE`, `region` au format d'une région GCP).

**Vérification :** une relecture du code ne trouve aucune valeur métier en dur dans le bloc
`module` ; `grep -n "variable" terraform/*.tf` ne remonte que `variables.tf` ; chaque variable a un
`type` et une `description`.

## T3. Valeurs d'entrée — `terraform.tfvars`

**Attendu :**

- les valeurs concrètes de la session de lab (`project_id`, `region`) et toute valeur que vous
  choisissez de ne pas laisser par défaut sont fournies dans un fichier **`terraform.tfvars`** ;
- ce fichier contient des identifiants propres à une session : il **n'est pas versionné**
  (`.gitignore`). Un fichier **`terraform.tfvars.example`** est versionné comme modèle, avec des
  valeurs d'exemple et un commentaire par ligne indiquant où trouver la valeur réelle (panneau du
  lab, `gcloud config get-value project`…) ;
- la documentation explique comment créer `terraform.tfvars` à partir du modèle en début de
  session.

**Vérification :** `cp terraform.tfvars.example terraform.tfvars`, saisie des deux valeurs du
lab, puis `terraform plan` fonctionne sans demander de variable manquante ; `git log -p` ne
contient aucun ID de projet réel.

## T4. Providers — `versions.tf`

**Attendu :**

- un fichier **`versions.tf`** contient le bloc `terraform { ... }` avec :
  - `required_version` : la version minimale de Terraform ;
  - `required_providers` : **tous** les providers utilisés par la configuration, chacun avec sa
    `source` et une contrainte de version épinglée (`~>`) ;
- les providers à déclarer sont ceux qu'exige le module GKE : consultez son fichier
  `versions.tf` (onglet *Dependencies* du Registry ou dépôt GitHub du module) et choisissez des
  contraintes **compatibles** avec celles du module (`google`, `google-beta`, et le cas échéant
  `kubernetes`) ;
- la configuration des providers (`provider "google" { project = var.project_id, region = ... }`)
  peut être placée dans `versions.tf` ou dans un `providers.tf` séparé, mais `required_providers`
  n'apparaît **qu'une seule fois** dans le dépôt ;
- le fichier `.terraform.lock.hcl` est versionné (il fige les versions exactes des providers) —
  justifiez ce choix dans la documentation.

**Vérification :** `terraform init` s'exécute sans erreur ni avertissement de version ;
`required_providers` n'apparaît que dans `versions.tf`.

## T5. Outputs — `outputs.tf`

**Attendu :**

- tous les outputs sont déclarés dans **`outputs.tf`**, chacun avec une `description` ;
- au minimum :

  | Output | Contenu |
  |---|---|
  | nom du cluster | `autopilot-cluster-1` (issu du module, pas recopié de la variable) |
  | région / location du cluster | région réelle du cluster |
  | `project_id` | projet dans lequel le cluster a été créé |
  | endpoint du plan de contrôle | adresse de l'API Kubernetes — marqué `sensitive = true` |
  | version de Kubernetes | version du plan de contrôle |
  | canal de release | canal effectivement appliqué |
  | commande de connexion | chaîne prête à copier : `gcloud container clusters get-credentials <nom> --location <région> --project <projet>` |

- les valeurs sont lues dans les **outputs du module** (consultez la liste des outputs du module
  sur le Registry), pas recopiées depuis les variables d'entrée.

**Vérification :** après `terraform apply`, `terraform output` affiche le nom du cluster, sa
région et la commande de connexion sans avoir à ouvrir la console GCP ; l'endpoint apparaît comme
`(sensitive value)` et se lit avec `terraform output -raw <nom>`.

## T6. Idempotence

**Attendu :** relancer `terraform apply` sur une infrastructure déjà conforme ne produit aucun
changement. Si le module produit une dérive persistante (un argument toujours détecté comme
modifié), vous devez l'identifier, l'expliquer et la documenter.

**Vérification :** juste après un `apply`, `terraform plan` affiche
`No changes. Your infrastructure matches the configuration.`

## T7. Qualité et commentaires

**Attendu :**

- `terraform fmt -check -recursive` et `terraform validate` passent sans erreur ;
- chaque fichier `.tf` commence par un commentaire décrivant son rôle ; chaque argument du module
  est commenté ;
- `.gitignore` couvre au minimum : `.terraform/`, `*.tfstate`, `*.tfstate.*`, `terraform.tfvars`,
  `crash.log`.

**Gestion du state :** le projet du lab est éphémère, un **state local** est donc acceptable.
Vous devez en revanche **documenter ce choix**, ses risques, et ce qu'il faudrait faire en
entreprise (bonus : backend distant GCS avec verrouillage).

**Vérification :** l'examinateur lance `terraform fmt -check` et `terraform validate` ; il lit
les commentaires de `main.tf` et doit comprendre chaque argument sans ouvrir la documentation du
module.

## T8. Connexion au cluster GKE

Une fois le cluster créé, `kubectl` doit pouvoir s'y connecter. Suivez la documentation Google
Cloud [Installer les plug-ins requis et stocker les informations du cluster pour kubectl](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl).

**Attendu :**

1. **Plugin d'authentification** : le plugin `gke-gcloud-auth-plugin` est installé sur le poste
   de contrôle et sa présence est vérifiée :

   ```bash
   gcloud components install gke-gcloud-auth-plugin   # ou le paquet de votre distribution
   gke-gcloud-auth-plugin --version
   ```

2. **Récupération des credentials** : les informations du cluster sont stockées dans le
   `kubeconfig` :

   ```bash
   gcloud container clusters get-credentials autopilot-cluster-1 \
     --location <REGION> --project <PROJECT_ID>
   ```

3. **Contrôle** : `kubectl config current-context` désigne le cluster GKE, et
   `kubectl cluster-info` répond.

4. **Bascule local / cloud** : la documentation explique comment passer du contexte minikube au
   contexte GKE (`kubectl config get-contexts`, `kubectl config use-context …`) et comment
   vérifier sur quel cluster on travaille **avant** tout `helm install` / `helm upgrade`.

**Vérification :** L'examinateur suit la procédure de la
documentation et obtient un `kubectl get namespaces` fonctionnel sur le cluster GKE.

## T9. Documentation Terraform dans le README

**Attendu :** le README de l'équipe (ou un `terraform/README.md` référencé par le README
principal) documente :

- **les ressources** : le module utilisé, sa version, ce qu'il crée réellement dans le projet
  (cluster, compte de service, éventuelles règles de firewall…) — consultez la sortie de
  `terraform plan` ou `terraform state list` ;
- **les variables** : tableau nom / description / type / valeur par défaut / obligatoire ;
- **les providers** : nom, source, contrainte de version, version effectivement installée ;
- **les outputs** : nom, description, exemple de valeur ;
- **les commandes** : `init`, `plan`, `apply`, `output`, `destroy`

**Vérification :** un consultant qui n'a jamais ouvert le code doit pouvoir, à la seule lecture du
README, savoir ce qui sera créé, quelles valeurs renseigner dans `terraform.tfvars`, et quelles
informations il récupérera en sortie.

---

## Points d'attention (lab Google Skills)

- **Durée** : la création comme la destruction d'un cluster Autopilot prennent plusieurs
  minutes. Lancez `terraform apply` en tout début de session.
- **Fin de session** : faites `helm uninstall` puis `terraform destroy` avant la fin du lab
