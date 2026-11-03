# Livre d'or Cloud — Projet 2

Application **Guestbook** (site PHP + base Redis leader / followers) rendue **persistante**,
packagée en **un chart Helm** et déployée en **`dev` / `staging` / `prod`**, en local sur
**minikube** et sur **GKE Autopilot** créé par **Terraform**.

> 🚧 Ce README est le **point d'entrée** de la documentation de transfert. Il sera complété au
> fil du projet.

## Documentation

👉 **[Sommaire de la documentation](docs/README.md)**, une partie par fichier, à lire dans l'ordre.

## Organisation du dossier

```
Project-2/
├── README.md       → ce fichier : point d'entrée
├── docs/           → documentation de transfert + captures d'écran
├── k8s/            → manifestes Kubernetes bruts, validés sur minikube
├── helm/           → chart Helm (à venir)
├── terraform/      → cluster GKE Autopilot (à venir)
└── enonce/         → énoncé du projet, non modifié
```

## Énoncé

L'énoncé du projet est conservé tel quel dans [`enonce/`](enonce/) :

| Fichier | Contenu |
|---|---|
| [`enonce/README.md`](enonce/README.md) | Énoncé principal |
| [`enonce/KUBERNETES.md`](enonce/KUBERNETES.md) | Exigences Kubernetes (K1 → K8) |
| [`enonce/HELM.md`](enonce/HELM.md) | Exigences Helm (H1 → H7) |
| [`enonce/TERRAFORM.md`](enonce/TERRAFORM.md) | Exigences Terraform (T1 → T9) |
