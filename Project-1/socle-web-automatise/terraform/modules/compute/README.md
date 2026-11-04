# Module Terraform `compute`

VM Compute Engine du socle, en **nombre paramétrable**, identifiées par des labels (lus par
l'inventaire dynamique Ansible) et par un tag réseau (ciblé par le firewall).

Documents liés : [référence des variables](../../../docs/variables.md#94-module-compute--modulescomputevariablestf) ·
[module `network`](../network/README.md) · [décisions techniques](../../../docs/decisions.md)
(ADR-06, ADR-07, ADR-12) · [runbooks](../../../docs/runbooks.md).

## Rôle

- Créer `instance_count` VM Debian 12 sur le sous-réseau fourni par le module `network`.
- Leur donner une IP publique éphémère (accès Ansible depuis le poste, consultation de la page).
- Poser les **labels** (`app`, `env`, `role`, `team`) et le **tag réseau** qui relient
  Terraform au firewall et à Ansible.
- Injecter la clé publique de déploiement par la métadonnée `ssh-keys` et désactiver OS Login.

Terraform crée les VM mais **n'y installe rien** (pas de `startup-script`) : toute la
configuration est faite ensuite par Ansible, avec le même code qu'en local.

Module autonome : il reçoit l'identifiant du sous-réseau en entrée (`subnetwork_id`) sans
connaître le module qui l'a créé.

## Ressources

Fichier : [`main.tf`](main.tf).

| Adresse | Type | Nom GCP (valeurs du socle) | Rôle |
|---|---|---|---|
| `google_compute_instance.this[0..N-1]` | VM Compute Engine (`count = var.instance_count`) | `format("%s-%d", var.name_prefix, count.index + 1)` : `fleetinfo-web-1`, `fleetinfo-web-2`... | Serveur web du socle |

Paramètres principaux de chaque VM :

| Paramètre | Valeur | Commentaire |
|---|---|---|
| `machine_type` | `var.machine_type` (`e2-small`) | Vérifier les types autorisés par le lab |
| `zone` | `var.zone` (ex. `us-central1-f`) | Une seule zone pour toutes les VM |
| `tags` | `var.network_tags` (`["fleetinfo-web"]`) | Cible des règles de firewall du module `network` |
| `labels` | `var.labels` (`app=fleetinfo`, `env=cloud`, `role=web`, `team=plateforme`) | Sélection et groupes de l'inventaire dynamique |
| `boot_disk` | `image = var.image` (`debian-cloud/debian-12`), `size = var.disk_size_gb` (10), `type = var.disk_type` (`pd-balanced`), `auto_delete = true` | Le disque disparaît avec la VM : rien ne survit à `terraform destroy` |
| `network_interface` | `subnetwork = var.subnetwork_id`, `access_config {}` | Bloc vide = IP publique éphémère |
| `metadata.ssh-keys` | `"${var.ssh_user}:${var.ssh_public_key}"` | L'agent invité GCE crée l'utilisateur `ansible`, sudoer sans mot de passe |
| `metadata.enable-oslogin` | `var.enable_os_login ? "TRUE" : "FALSE"` (`"FALSE"`) | Garantit la prise en compte de `ssh-keys` même si le projet active OS Login |
| `allow_stopping_for_update` | `true` | Terraform peut arrêter la VM pour appliquer un changement de `machine_type` |

## Entrées

Fichier : [`variables.tf`](variables.tf).

| Nom | Type | Défaut | Sensible | Description |
|---|---|---|---|---|
| `instance_count` | `number` | — | non | Nombre de VM à créer. |
| `name_prefix` | `string` | — | non | Préfixe des noms de VM ; un suffixe `-1`, `-2`... est ajouté. |
| `zone` | `string` | — | non | Zone des VM. |
| `machine_type` | `string` | — | non | Type de machine Compute Engine. |
| `image` | `string` | — | non | Image (ou famille d'images) de démarrage. |
| `disk_size_gb` | `number` | — | non | Taille du disque de démarrage, en Go. |
| `disk_type` | `string` | — | non | Type du disque de démarrage. |
| `subnetwork_id` | `string` | — | non | Identifiant du sous-réseau (sortie `subnet_id` du module `network`). |
| `network_tags` | `list(string)` | — | non | Tags réseau des VM (cibles des règles de firewall). |
| `labels` | `map(string)` | — | non | Labels des VM (au minimum `env`, `role`, `team`). Validation : ces trois clés sont obligatoires, sinon « Les labels doivent contenir au minimum les clés env, role et team. » |
| `ssh_user` | `string` | — | non | Utilisateur SSH créé sur les VM à partir de la métadonnée `ssh-keys`. |
| `ssh_public_key` | `string` | — | non | Contenu de la clé publique SSH (format OpenSSH, une ligne). |
| `enable_os_login` | `bool` | `false` | non | Active OS Login sur les VM (désactivé : l'accès se fait par la métadonnée `ssh-keys`). |

## Sorties

Fichier : [`outputs.tf`](outputs.tf).

| Nom | Valeur | Description |
|---|---|---|
| `instance_names` | `google_compute_instance.this[*].name` | Noms des VM, dans l'ordre de création. |
| `public_ips` | `{ nom de VM => network_interface[0].access_config[0].nat_ip }` | IP publiques des VM, par nom de VM. |
| `internal_ips` | `{ nom de VM => network_interface[0].network_ip }` | IP internes des VM, par nom de VM. |
| `self_links` | `google_compute_instance.this[*].self_link` | Liens complets (`self_link`) des VM. |

La racine ré-expose `instance_names` (`vm_names`), `public_ips` (`vm_public_ips`) et
`internal_ips` (`vm_internal_ips`), et en dérive `fleetinfo_urls`, `health_urls` et
`ssh_commands`. `self_links` n'est pas ré-exposé.

## Exemple d'appel

Extrait de [`terraform/main.tf`](../../main.tf) :

```hcl
module "compute" {
  source = "./modules/compute"

  instance_count = var.vm_count
  name_prefix    = "${var.name_prefix}-${var.server_role}"
  zone           = var.zone
  machine_type   = var.machine_type
  image          = var.vm_image
  disk_size_gb   = var.boot_disk_size_gb
  disk_type      = var.boot_disk_type
  subnetwork_id  = module.network.subnet_id # sortie du module réseau -> entrée du module VM
  network_tags   = [var.network_tag]
  labels         = local.vm_labels
  ssh_user       = var.ssh_user
  ssh_public_key = local.ssh_public_key
}
```

Avec, dans [`terraform/locals.tf`](../../locals.tf) :

```hcl
vm_labels = {
  app  = var.app_name
  env  = var.environment
  role = var.server_role
  team = var.team
}

ssh_public_key = trimspace(file(var.ssh_public_key_path))
```

`enable_os_login` n'est pas passée : sa valeur par défaut `false` s'applique.

## Notes

- **`count` plutôt que `for_each`** ([ADR-12](../../../docs/decisions.md)). Passer de 2 à 3 VM ne
  demande que de changer `vm_count` dans `terraform.tfvars` (2 à 10, validation de la racine),
  jamais le code du module. En
  réduisant le nombre, Terraform supprime les VM de plus fort indice (`fleetinfo-web-3`, puis
  `-2`...). Contrepartie : impossible de retirer une VM « au milieu » sans renommer les
  suivantes ; un `for_each` sur une liste de noms le permettrait, au prix d'une variable plus
  complexe à renseigner.
- **Labels et inventaire dynamique.** `app` sert de filtre de sélection
  (`labels.app = fleetinfo`), `role` produit le groupe Ansible `web` (même nom qu'en local),
  `env` le groupe `env_cloud`. La validation du module exige `env`, `role` et `team` (consigne
  du projet) ; `app`, indispensable à l'inventaire, est garanti par `locals.tf` à la racine.
  Ajouter une VM côté Terraform ne demande **aucune modification du code Ansible** : elle porte
  les mêmes labels et apparaît d'elle-même dans le groupe `web`.
- **Tag réseau.** Le tag `fleetinfo-web` est la seule cible des règles de firewall du module
  `network` ; une VM sans ce tag ne recevrait ni HTTP ni SSH.
- **OS Login désactivé** (`enable-oslogin = "FALSE"`, [ADR-06](../../../docs/decisions.md)) : la
  métadonnée d'instance garantit la prise en compte de `ssh-keys` même si le projet du lab active
  OS Login au niveau projet. Si une contrainte d'organisation imposait OS Login
  (`constraints/compute.requireOsLogin`), cette métadonnée ne suffirait pas : il faudrait passer
  à OS Login (alternative décrite dans l'ADR).
- **Clé SSH.** Seule la clé **publique** transite par Terraform (lue dans
  `local/ssh/fleet_key.pub`, générée par `local/scripts/generate-keys.sh`). La clé privée n'est
  jamais dans le code ni dans le state. Aucune entrée de ce module n'est sensible : une clé
  publique n'est pas un secret.
- **IP publique éphémère.** Elle est libérée quand la VM est arrêtée : un arrêt / redémarrage (y
  compris celui provoqué par un changement de `machine_type`, autorisé par
  `allow_stopping_for_update`) peut donner une nouvelle IP. L'inventaire dynamique la relit à
  chaque exécution. `terraform output vm_public_ips` lit le state : si l'arrêt a eu lieu hors de
  Terraform (console, `gcloud`), mettre d'abord le state à jour avec
  `terraform -chdir=terraform apply -refresh-only` (depuis `socle-web-automatise/`). Si une IP déjà connue est
  réattribuée à une autre VM, SSH refuse la connexion (« REMOTE HOST IDENTIFICATION HAS
  CHANGED ») : `ssh-keygen -R <ip>` dans le controller ([dépannage](../../../docs/troubleshooting.md)).
- **Image.** `debian-cloud/debian-12` désigne la famille : chaque VM est créée sur la dernière
  image Debian 12 publiée par Google ; le rôle Ansible `common` vérifie ensuite qu'il s'agit bien
  d'une Debian 12 sous systemd.
- **Provider** : pas de bloc `required_providers` dans le module ; il hérite du provider
  `hashicorp/google` de la racine (`versions.tf`, `google ~> 8.9`).

## Vérification

Résultat attendu après `terraform apply` sur une session de lab (à confirmer lors de la
répétition générale), depuis `socle-web-automatise/` :

```bash
terraform -chdir=terraform output vm_names
terraform -chdir=terraform output vm_public_ips
gcloud compute instances list --filter="labels.app=fleetinfo" --format="table(name,zone.basename(),machineType.basename(),status,tags.items.list(),labels.list())"
```

Résultat attendu : `["fleetinfo-web-1", "fleetinfo-web-2"]` ; une IP publique par VM ; deux VM
`RUNNING` en `e2-small` dans la zone choisie, tag `fleetinfo-web`, labels
`app=fleetinfo,env=cloud,role=web,team=plateforme`.

Ajouter une VM (runbook complet : [runbooks](../../../docs/runbooks.md)) :

```bash
# terraform/terraform.tfvars : vm_count = 3
terraform -chdir=terraform plan     # attendu : Plan: 1 to add, 0 to change, 0 to destroy.
terraform -chdir=terraform apply
terraform -chdir=terraform plan     # attendu : No changes.
```

Puis, dans le controller : `ansible-inventory -i inventories/cloud/fleet.gcp.yml --graph` (la
VM `fleetinfo-web-3` apparaît dans `web`) et
`ansible-playbook -i inventories/cloud/fleet.gcp.yml site.yml`, sans aucune modification du code
Ansible.
