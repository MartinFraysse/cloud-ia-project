---
marp: true
paginate: true
size: 16:9
footer: "Livre d'or Cloud · Passation équipe Plateforme"
style: |
  /* ===== Palette (code couleur de la doc) ===== */
  :root {
    --bg: #0f172a;          /* fond : bleu nuit */
    --panel: #1e293b;       /* cartes */
    --text: #e2e8f0;
    --muted: #94a3b8;
    --accent: #22d3ee;      /* cyan : Services / fil conducteur */
    --frontend: #8b5cf6;    /* violet */
    --leader: #ef4444;      /* rouge */
    --follower: #22c55e;    /* vert */
    --storage: #f97316;     /* orange */
    --terraform: #ec4899;   /* rose */
    --helm: #3b82f6;        /* bleu */
  }

  section {
    background: var(--bg);
    color: var(--text);
    font-family: "Inter", "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 28px;
    padding: 60px 80px;
    justify-content: flex-start;
  }
  h1, h2 { color: #fff; margin: 0 0 30px 0; }
  h2 {
    font-size: 44px;
    border-left: 10px solid var(--accent);
    padding-left: 20px;
  }
  strong { color: var(--accent); }
  code { background: var(--panel); color: #f8fafc; border-radius: 6px; padding: 2px 8px; }
  pre { background: #020617; border-radius: 12px; border: 1px solid #334155; font-size: 22px; }
  pre code { background: transparent; padding: 0; }
  /* Coloration du code, lisible sur fond sombre */
  pre code, pre code span { color: #e2e8f0; }
  pre .hljs-attr, pre .hljs-name, pre .hljs-keyword, pre .hljs-built_in { color: #7dd3fc; }
  pre .hljs-string { color: #fca5a5; }
  pre .hljs-number, pre .hljs-literal, pre .hljs-bullet { color: #fbbf24; }
  pre .hljs-comment { color: #64748b; font-style: italic; }
  ul { margin: 0; }
  li { margin: 10px 0; }
  li::marker { color: var(--accent); }

  table { border-collapse: collapse; font-size: 26px; margin-top: 10px; }
  table tr, table tr:nth-child(2n) { background: var(--bg) !important; }
  table th { background: var(--panel) !important; color: var(--accent); }
  table td { background: var(--bg) !important; color: var(--text); }
  table th, table td { border: none; border-bottom: 1px solid #334155; padding: 14px 28px; }

  section > p:has(> img) { text-align: center; }
  img { border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,.5); background: transparent; }

  footer { color: var(--muted); font-size: 16px; }
  section::after { color: var(--muted); font-size: 18px; }   /* numéro de page */

  /* ===== Slide de titre ===== */
  section.lead { justify-content: center; text-align: left; }
  section.lead h1 { font-size: 80px; margin-bottom: 10px; }
  section.lead h1::after {
    content: ""; display: block; width: 180px; height: 8px; margin-top: 24px;
    background: linear-gradient(90deg, var(--terraform), var(--helm), var(--accent));
    border-radius: 4px;
  }
  section.lead p { color: var(--muted); font-size: 30px; }

  /* ===== Intercalaire de partie ===== */
  section.part { justify-content: center; }
  section.part h1 { font-size: 72px; }
  section.part h1 em { display: block; font-style: normal; font-size: 120px; color: var(--accent); }
  section.part p { color: var(--muted); }

  /* ===== Deux colonnes : texte à gauche, image à droite ===== */
  section.split {
    display: grid;
    grid-template-columns: 1fr 1.2fr;
    grid-template-rows: auto 1fr;
    column-gap: 50px;
    align-items: center;
  }
  section.split h2 { grid-column: 1 / 3; align-self: start; }
  section.split > ul { grid-column: 1; }
  section.split > p { grid-column: 2; text-align: center; }

  /* ===== Chaîne d'étapes : liste numérotée en cartes horizontales ===== */
  section.flow ol {
    display: flex; gap: 22px; padding: 0; list-style: none; margin-top: 40px;
    counter-reset: step;
  }
  section.flow ol li {
    flex: 1; background: var(--panel); border-radius: 14px; padding: 26px 22px;
    margin: 0; font-size: 24px; position: relative; border-top: 6px solid var(--accent);
    counter-increment: step;
  }
  section.flow ol li::before {
    content: counter(step); display: block; font-size: 40px; font-weight: 800;
    color: var(--accent); margin-bottom: 8px;
  }
  section.flow ol li:nth-child(1) { border-top-color: var(--terraform); }
  section.flow ol li:nth-child(1)::before { color: var(--terraform); }
  section.flow ol li:nth-child(2) { border-top-color: var(--helm); }
  section.flow ol li:nth-child(2)::before { color: var(--helm); }
  section.flow ol li:nth-child(3) { border-top-color: var(--frontend); }
  section.flow ol li:nth-child(3)::before { color: var(--frontend); }
  section.flow ol li:nth-child(4) { border-top-color: var(--follower); }
  section.flow ol li:nth-child(4)::before { color: var(--follower); }

  /* ===== Grande image seule ===== */
  section.shot { justify-content: center; align-items: center; }
  section.shot p { text-align: center; color: var(--muted); }
---

<!-- _class: lead -->
<!-- _paginate: false -->
<!-- _footer: "" -->

# Livre d'or Cloud

GKE · Terraform · Helm — passation à l'équipe d'exploitation

Équipe Plateforme · ESIEA S9

---

## Le contexte

- **Cloud Hôtels** : une quarantaine d'hôtels
- Un **livre d'or numérique** : le client écrit un message en fin de séjour
- Les messages s'affichent dans le hall de l'hôtel
- Un prototype existe : l'application **Guestbook** (site PHP + Redis)

---

## Ce qu'on nous a demandé

| # | Objectif | Comment |
|---|---|---|
| 1 | **Ne perdre aucun message** | Disque persistant |
| 2 | **Héberger dans le cloud** | Cluster GKE Autopilot |
| 3 | **Créer le cluster en code** | Terraform |
| 4 | **3 environnements isolés** | Un chart Helm : dev, staging, prod |
| 5 | **Travailler en local** | minikube, même chart |

---

## Au programme

1. Le problème
2. L'architecture
3. Kubernetes et persistance
4. Helm : un chart, 3 environnements
5. Terraform et le cloud
6. Exploitation, décisions, limites
7. Démonstration

---

<!-- _class: part -->
<!-- _paginate: false -->

# <em>01</em> Le problème

Un prototype qui perd ses messages

---

<!-- _class: split -->

## Le livre d'or fonctionne…

- Application d'origine du tutoriel Kubernetes
- Installée telle quelle sur minikube
- On écrit **3 messages**

![w:560](../docs/screenshots/08-messages-avant-suppression.png)

---

## … jusqu'au redémarrage de Redis

On simule une panne : on supprime le pod de la base.

```bash
kubectl delete pod -n tuto -l role=leader
```

![w:1000](../docs/screenshots/09-suppression-pod-leader.png)

Kubernetes recrée aussitôt un nouveau pod.

---

<!-- _class: split -->

## Résultat : tout est perdu

- Le nouveau pod Redis démarre **vide**
- Les 3 messages ont **disparu**
- C'est le problème vécu par le client

![h:420](../docs/screenshots/10-messages-perdus.png)

---

## D'où ça vient : le Deployment `redis-leader`

```yaml
# k8s/tutoriel-origine/redis-leader-deployment.yaml (extrait)
    spec:
      containers:
      - name: leader
        image: "docker.io/redis:6.0.5"
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        ports:
        - containerPort: 6379
      # ❌ pas de volumeMounts : rien n'est monté sur /data
      # ❌ pas de volumes : aucun disque
      # ❌ pas de fichier de configuration Redis
```

Redis garde les messages **dans le conteneur**. Le pod disparaît → les données aussi.

---

## D'où ça vient : les fichiers fournis

```text
k8s/tutoriel-origine/
├── frontend-deployment.yaml
├── frontend-service.yaml
├── redis-follower-deployment.yaml
├── redis-follower-service.yaml
├── redis-leader-deployment.yaml
└── redis-leader-service.yaml
```

- ❌ Aucun **PersistentVolumeClaim** : pas de disque persistant
- ❌ Aucune **ConfigMap** : pas de `redis.conf`, donc pas de journal AOF
- Uniquement des Deployments et des Services

---

<!-- _class: part -->
<!-- _paginate: false -->

# <em>02</em> L'architecture

Terraform crée le cluster, Helm installe l'application

---

## Vue d'ensemble : local et cloud

![h:360](diagrams/02-vue-ensemble.png)

- **Terraform** → ressources Google : le cluster
- **Helm** → objets Kubernetes : l'application, **le même chart** en local et sur GKE

---

## Ce que contient un environnement

![w:1100](diagrams/03-namespace.png)

- Le **leader** écrit chaque message sur un **disque persistant** (PVC)
- Installé **3 fois** : `stack-dev`, `stack-staging`, `stack-prod`, un namespace chacun

---

## Les objets d'une release

| Composant | Deployment | Service | ConfigMap | Disque |
|---|---|---|---|---|
| frontend | ✅ | `LoadBalancer` | adresses Redis | — |
| redis-leader | ✅ `Recreate` | `ClusterIP` 6379 | `redis.conf` | PVC |
| redis-follower | ✅ | `ClusterIP` 6379 | adresse du leader | — |

**10 objets**, tous nommés `stack-<ENV>-guestbook-…`

---

<!-- _class: part -->
<!-- _paginate: false -->

# <em>03</em> La persistance

Les messages survivent au redémarrage de Redis

---

## Le principe : un disque pour Redis

![w:1150](diagrams/04-persistance.png)

| Fichier | Rôle |
|---|---|
| `redis-leader-pvc.yaml` | **Nouveau** : demande un disque de 1Gi |
| `redis-leader-configmap.yaml` | **Nouveau** : dit à Redis d'écrire sur ce disque |
| `redis-leader-deployment.yaml` | **Modifié** : branche le disque et la configuration |

---

## ① Le PVC : demander un disque

```yaml
# k8s/redis-leader-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-leader-data
spec:
  accessModes:
    - ReadWriteOnce        # un seul nœud à la fois : il n'y a qu'un leader
  resources:
    requests:
      storage: 1Gi
  # pas de storageClassName → classe par défaut du cluster
```

- minikube : `standard` · GKE : `standard-rwo` (disque persistant Google)

---

## ② La ConfigMap : configurer Redis

```yaml
# k8s/redis-leader-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-leader-config
data:
  redis.conf: |
    dir /data          # écrire sur le disque persistant
    appendonly yes     # journal AOF : chaque message est enregistré
```

- Sans ce fichier, Redis garde tout **en mémoire**
- AOF : enregistré sur disque **toutes les secondes** → au pire 1 s perdue

---

## ③ Le Deployment : tout brancher

```yaml
# k8s/redis-leader-deployment.yaml (extrait, condensé)
spec:
  strategy:
    type: Recreate                       # arrêter l'ancien Redis AVANT le nouveau
  template:
    spec:
      containers:
        - name: leader
          args: ["redis-server", "/etc/redis/redis.conf"]   # lancer avec notre config
          volumeMounts:
            - { name: data,   mountPath: /data }             # le disque
            - { name: config, mountPath: /etc/redis, readOnly: true }
      volumes:
        - { name: data,   persistentVolumeClaim: { claimName: redis-leader-data } }
        - { name: config, configMap: { name: redis-leader-config } }
```

- **`Recreate`** : le disque `ReadWriteOnce` ne se branche qu'à un seul Redis à la fois

---

## Preuve : la configuration est active

![w:950](../docs/screenshots/19-verification-config-redis.png)

`dir` → **`/data`** · `appendonly` → **`yes`** · le journal **`appendonly.aof`** est sur le disque

---

## Preuve : on refait le test de la panne

![w:820](../docs/screenshots/20-suppression-pod-leader-persistance.png)

Même commande qu'au début : on supprime le pod Redis, Kubernetes en recrée un.

---

<!-- _class: split -->

## Résultat : les messages sont toujours là

- Le nouveau pod rebranche **le même disque**
- Redis relit son journal **AOF**
- Testé aussi après un **redémarrage complet** de minikube

![h:380](../docs/screenshots/21-messages-conserves-apres-suppression.png)

