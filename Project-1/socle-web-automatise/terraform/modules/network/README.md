# Module Terraform `network`

Réseau du socle sur Google Cloud : un VPC dédié, un sous-réseau et deux règles de firewall
(HTTP ouvert, SSH restreint) qui ciblent les VM **par tag réseau**.

Documents liés : [référence des variables](../../../docs/variables.md#93-module-network--modulesnetworkvariablestf) ·
[module `compute`](../compute/README.md) · [décisions techniques](../../../docs/decisions.md)
(ADR-06, ADR-12) · [runbooks](../../../docs/runbooks.md).

## Rôle

- Isoler le socle dans son **propre VPC** (pas le réseau `default`), en mode personnalisé : aucun
  sous-réseau n'est créé automatiquement dans les autres régions.
- Fournir au module `compute` l'identifiant du sous-réseau (`subnet_id`).
- Ouvrir le strict nécessaire en entrée : HTTP pour la page Fleet Info, SSH pour Ansible depuis
  le seul poste de l'opérateur.

Module autonome : il ne connaît que ses variables d'entrée, expose ses sorties et ne référence
aucune ressource d'un autre module.

## Ressources

Fichier : [`main.tf`](main.tf).

| Adresse | Type | Nom GCP (valeurs du socle) | Rôle |
|---|---|---|---|
| `google_compute_network.this` | VPC | `var.network_name` (`fleetinfo-vpc`) | VPC dédié, `auto_create_subnetworks = false` |
| `google_compute_subnetwork.this` | Sous-réseau | `var.subnet_name` (`fleetinfo-subnet-us-central1`) | Plage `var.subnet_cidr` (`10.10.0.0/24`) dans `var.region` |
| `google_compute_firewall.allow_http` | Règle de firewall | `${var.network_name}-allow-http` (`fleetinfo-vpc-allow-http`) | `INGRESS`, TCP `var.http_port` (80) depuis `var.http_source_ranges` (`0.0.0.0/0`), vers le tag `var.target_tag` |
| `google_compute_firewall.allow_ssh` | Règle de firewall | `${var.network_name}-allow-ssh` (`fleetinfo-vpc-allow-ssh`) | `INGRESS`, TCP `var.ssh_port` (22) depuis `var.ssh_source_ranges` (IP de l'opérateur en `/32`), vers le tag `var.target_tag` |

Les valeurs entre parenthèses sont celles obtenues avec les défauts de la racine et
`region = "us-central1"`.

## Entrées

Fichier : [`variables.tf`](variables.tf). Toutes les entrées sont **obligatoires** (aucune
valeur par défaut) : c'est la racine qui décide.

| Nom | Type | Défaut | Sensible | Description |
|---|---|---|---|---|
| `network_name` | `string` | — | non | Nom du VPC (unique dans le projet) ; préfixe des noms des règles de firewall. |
| `subnet_name` | `string` | — | non | Nom du sous-réseau. |
| `region` | `string` | — | non | Région du sous-réseau. |
| `subnet_cidr` | `string` | — | non | Plage CIDR du sous-réseau. |
| `target_tag` | `string` | — | non | Tag réseau des VM ciblées par les règles de firewall. |
| `http_port` | `number` | — | non | Port TCP HTTP autorisé en entrée. |
| `http_source_ranges` | `list(string)` | — | non | Plages CIDR autorisées sur le port HTTP. |
| `ssh_port` | `number` | — | non | Port TCP SSH autorisé en entrée. |
| `ssh_source_ranges` | `list(string)` | — | **oui** | Plages CIDR autorisées sur le port SSH (IP de l'opérateur). |

## Sorties

Fichier : [`outputs.tf`](outputs.tf).

| Nom | Valeur | Description |
|---|---|---|
| `network_id` | `google_compute_network.this.id` | Identifiant complet du VPC. |
| `network_name` | `google_compute_network.this.name` | Nom du VPC. |
| `subnet_id` | `google_compute_subnetwork.this.id` | Identifiant complet du sous-réseau, à fournir au module `compute`. |
| `subnet_name` | `google_compute_subnetwork.this.name` | Nom du sous-réseau. |
| `subnet_cidr` | `google_compute_subnetwork.this.ip_cidr_range` | Plage CIDR effective du sous-réseau. |
| `firewall_rule_names` | `[allow_http.name, allow_ssh.name]` | Noms des règles de firewall créées. |

La racine ré-expose `network_name`, `subnet_name`, `subnet_cidr` et `firewall_rule_names` (sous
le nom `firewall_rules`) ; `subnet_id` est consommé par le module `compute` ; `network_id` n'est
pas ré-exposé.

## Exemple d'appel

Extrait de [`terraform/main.tf`](../../main.tf) :

```hcl
module "network" {
  source = "./modules/network"

  network_name       = "${var.name_prefix}-vpc"
  subnet_name        = "${var.name_prefix}-subnet-${var.region}"
  region             = var.region
  subnet_cidr        = var.subnet_cidr
  target_tag         = var.network_tag
  http_port          = var.http_port
  http_source_ranges = var.http_source_ranges
  ssh_port           = var.ssh_port
  ssh_source_ranges  = var.ssh_source_ranges
}
```

Liaison avec le module `compute` (même fichier) : `subnetwork_id = module.network.subnet_id`.

## Notes

- **Ciblage par tag réseau.** Les deux règles portent `target_tags = [var.target_tag]` : elles ne
  s'appliquent qu'aux VM qui portent ce tag (`fleetinfo-web`, posé par le module `compute` via
  `network_tags`), jamais à « toutes les instances » du réseau. Le même tag doit donc être
  transmis aux deux modules ; la racine le garantit avec la seule variable `network_tag`.
- **SSH restreint.** Seules les plages de `ssh_source_ranges` (l'IP publique du poste de
  l'opérateur, en `/32`) atteignent le port 22 ; c'est le seul point d'entrée d'Ansible. Le
  contrôle des plages (CIDR IPv4 de préfixe `/16` minimum : `0.0.0.0/0`, `0.0.0.0/1` et l'IPv6
  sont refusés) est une **validation de la variable racine** (`terraform/variables.tf`) : le
  module lui-même n'en porte pas ; s'il est réutilisé ailleurs, reproduire cette validation. Si l'IP publique de
  l'opérateur change, mettre à jour `ssh_source_ranges` dans `terraform.tfvars` puis
  `terraform apply` (seule la règle `allow_ssh` est modifiée). Alternatives écartées (OS Login,
  IAP TCP forwarding `35.235.240.0/20`) : [ADR-06](../../../docs/decisions.md).
- **`sensitive = true`** sur `ssh_source_ranges`, ici comme à la racine : `terraform plan` affiche
  `source_ranges = (sensitive value)` pour la règle SSH (vérifié). La valeur reste en clair dans
  le state et dans `terraform.tfvars`, tous deux ignorés par Git.
- **HTTP ouvert à Internet** par défaut (`http_source_ranges = ["0.0.0.0/0"]` à la racine) : la
  page Fleet Info et `/health` sont publics ; `/status` est protégé par mot de passe côté nginx.
  HTTP seulement, pas de TLS (limite connue).
- **Règles implicites de GCP** : tout VPC refuse par défaut le trafic entrant et autorise le
  trafic sortant. Le module n'ajoute donc aucune règle de sortie ; les VM sortent sur Internet
  par leur IP publique (installation des paquets), sans Cloud NAT.
- **Labels** : les ressources réseau n'en portent pas ; les labels `app`, `env`, `role`, `team`
  sont posés sur les VM par le module `compute`.
- **Provider** : le module ne déclare pas de bloc `required_providers` ; il hérite du provider
  `hashicorp/google` configuré à la racine (`versions.tf` est l'unique déclaration des versions
  du projet : `google ~> 8.9`, verrouillé en 8.9.0 dans `.terraform.lock.hcl`).

## Vérification

Résultat de `terraform plan` vérifié hors ligne (sans session de lab) : `Plan: 6 to add`, dont
les 4 ressources de ce module (VPC, sous-réseau, 2 règles) et les 2 VM du module `compute`.

Après `terraform apply` sur une session de lab (résultat attendu, à confirmer lors de la
répétition générale), depuis `socle-web-automatise/` :

```bash
terraform -chdir=terraform output network_name
terraform -chdir=terraform output subnet_name
terraform -chdir=terraform output firewall_rules
gcloud compute firewall-rules list --filter="network:fleetinfo-vpc" --format="table(name,sourceRanges.list(),allowed[].map().firewall_rule().list(),targetTags.list())"
```

Résultat attendu : `"fleetinfo-vpc"`, `"fleetinfo-subnet-us-central1"`, la liste
`["fleetinfo-vpc-allow-http", "fleetinfo-vpc-allow-ssh"]`, puis les deux règles avec
`0.0.0.0/0` / `tcp:80` et `203.0.113.10/32` (votre IP) / `tcp:22`, toutes deux sur le tag
`fleetinfo-web`.
