# Manifestes d'origine du tutoriel Guestbook

Ces 6 fichiers sont **la copie exacte, non modifiée**, des manifestes du tutoriel officiel.
Ils servent uniquement à :

1. **reproduire le problème du client** : les messages sont perdus quand la base redémarre ;
2. **comparer** avec nos manifestes améliorés (dossier [`../`](../)).

> ⚠️ Ne pas les utiliser pour les environnements `dev`, `staging` ou `prod`.
> Ils n'ont ni persistance, ni contrôles de santé, ni limites de ressources.

## Source

| | |
|---|---|
| Dépôt | [GoogleCloudPlatform/kubernetes-engine-samples](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/main/quickstarts/guestbook) |
| Dossier | `quickstarts/guestbook` |
| Dernier commit du dossier au moment de la copie | `56c10ef` (2025-07-04) |
| Date de la copie | 2026-11-02 |
| Licence | Apache 2.0 (en-tête de chaque fichier) |

## Contenu

| Fichier | Objet créé |
|---|---|
| `redis-leader-deployment.yaml` | Base Redis principale (écritures) |
| `redis-leader-service.yaml` | Nom réseau `redis-leader` |
| `redis-follower-deployment.yaml` | 2 copies Redis (lectures) |
| `redis-follower-service.yaml` | Nom réseau `redis-follower` |
| `frontend-deployment.yaml` | 3 pods du site web PHP |
| `frontend-service.yaml` | Accès au site (`LoadBalancer`, port 80) |

## Utilisation (cluster local minikube)

```bash
kubectl config current-context                    # doit afficher : minikube
kubectl create namespace tuto
kubectl apply -n tuto -f Project-2/k8s/tutoriel-origine/
kubectl get pods -n tuto -w                        # Ctrl+C quand tout est Running
```

Dans un autre terminal : `minikube tunnel` (à laisser ouvert). Puis :

```bash
kubectl get svc frontend -n tuto     # colonne EXTERNAL-IP
```

Ouvrir `http://<EXTERNAL-IP>` (sous Linux : une IP du cluster, ex. `10.105.199.2` ;
sous macOS / Windows : `127.0.0.1`).

Nettoyage :

```bash
kubectl delete namespace tuto
```

## Ce qui manque (corrigé dans nos manifestes)

| Manque | Corrigé dans |
|---|---|
| Aucun contrôle de santé (readiness / liveness) | Partie 3 |
| Pas de limites de ressources (seulement des *requests*) | Partie 3 |
| Réglage `GET_HOSTS_FROM` écrit directement dans le Deployment | Partie 3 (ConfigMap) |
| Étiquettes non standard (`app`, `role`, `tier`) | Partie 3 |
| Les Deployments leader et follower ont le **même sélecteur** (`app: redis`) | Partie 3 |
| **Aucune persistance** : la base perd tout au redémarrage | Partie 4 |
