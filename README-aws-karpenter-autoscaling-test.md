# Test d'Autoscaling - Déployer l'Application PHP-Apache et Tester Karpenter

Ce guide détaillé couvre :
- 📦 Déploiement de l'application PHP-Apache avec HPA
- 🚀 Phase 1 : Scale-UP (augmentation de la charge)
- 📉 Phase 2 : Scale-DOWN (consolidation des nodes)
- 🔍 Monitoring et observation en temps réel
- 🧹 Nettoyage après les tests
- 🆘 Dépannage des problèmes courants

Ce guide vous montre comment déployer l'application de démonstration et tester le **double-level autoscaling** : HPA (Horizontal Pod Autoscaler) pour les pods et Karpenter pour les nodes EC2.

---

## 📋 Prérequis

Avant de commencer, assurez-vous que :

✅ **Cluster EKS créé** et opérationnel
✅ **Karpenter installé** et fonctionnant
✅ **metrics-server déployé** (essentiel pour HPA)
✅ **kubectl configuré** pour accéder au cluster

### Vérification Rapide

```bash
# Vérifier que le cluster répond
kubectl cluster-info

# Vérifier que Karpenter est actif
kubectl get pods -n karpenter

# Vérifier que metrics-server est prêt
kubectl get deployment metrics-server -n kube-system
```

---

## 🚀 Étape 1 : Déployer l'Application PHP-Apache

### 1.1 — Configuration de l'Application

L'application de démonstration est configurée avec :

- **Image** : `k8s.gcr.io/hpa-example` (application simple qui consomme du CPU)
- **Déploiement initial** : 1 réplique
- **Limite de répliques** : 10 replicas maximum
- **Seuil de scaling HPA** : Scale-up si l'utilisation CPU dépasse 50%
- **Resources**:
  - CPU request: 200m (utilisé par HPA pour calculer les métriques)
  - CPU limit: 500m

### 1.2 — Déployer l'Application et le HPA

Les fichiers de déploiement sont fournis dans le répertoire `k8s/base/` :

```bash
# Déployer tous les objets Kubernetes (Deployment + Service + HPA)
kubectl apply -k ./k8s/base
```

**Fichiers déployés** :
- `k8s/base/deployment.yaml` - Application php-apache
- `k8s/base/service.yaml` - Service pour accéder à l'application
- `k8s/base/hpa.yaml` - Horizontal Pod Autoscaler

### 1.3 — Vérifier le Déploiement Initial

```bash
# Vérifier le déploiement
kubectl get deployment php-apache
kubectl get pods -n default

# Vérifier que le service est créé
kubectl get svc php-apache

# Vérifier que le HPA est créé et opérationnel
kubectl get hpa php-apache-hpa
kubectl describe hpa php-apache-hpa
```

**Résultat attendu** :

```
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
php-apache  1/1     1            1           10s

NAME        REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
php-apache-hpa  Deployment/php-apache  0%/50%    1         10        1          5s
```

---

## ⚙️ Étape 2 : Vérifications Préalables au Test

Avant de déclencher le test d'autoscaling, assurez-vous que tout est prêt :

```bash
# 1. Vérifier que metrics-server est actif (ESSENTIEL pour HPA)
kubectl get pods -n kube-system -l k8s-app=metrics-server
# Résultat attendu : pod avec statut Running

# 2. Vérifier l'état initial du cluster
echo "=== NODES SYSTÈME ==="
kubectl get nodes -L role

echo "=== PODS INITIAUX ==="
kubectl get pods -A --sort-by=.metadata.namespace

echo "=== HPA STATUS ==="
kubectl get hpa php-apache-hpa

echo "=== TAINTS SYSTEM NODES ==="
kubectl describe nodes | grep -A 2 "Taints:"
```

**Vous devriez voir** :
- ✅ 2 nodes système (avec label `role=system` et taint `CriticalAddonsOnly`)
- ✅ 1 pod php-apache initial en état `Running`
- ✅ HPA affichant `0%/50%` (0% CPU utilisé, seuil à 50%)
- ✅ metrics-server en état `Running`

---

## 🚀 Étape 3 : Déclencher le Test d'Autoscaling (Phase 1 - Scale UP)

Le test se déroule en deux phases : scale-up (augmentation de la charge) et scale-down (réduction).

### Concept : Double-Level Autoscaling

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  UTILISATEUR ┌──────────────────┐                      │
│      │       │  Load Generator  │                      │
│      │       │ (charge CPU ↑)   │                      │
│      └──────→└──────────────────┘                      │
│                       │                                │
│                       ↓                                │
│            ┌──────────────────────┐                   │
│            │  HPA (Horizontal Pod │                   │
│            │    Autoscaler)       │                   │
│            │  Détecte CPU > 50%   │                   │
│            └──────────────────────┘                   │
│                       │                                │
│                       ↓                                │
│           Replicas: 1 → 2 → 5 → 10                    │
│           (Pods supplémentaires)                      │
│                       │                                │
│                       ↓                                │
│            ┌──────────────────────┐                   │
│            │ KARPENTER détecte    │                   │
│            │ pods Pending (non    │                   │
│            │ placés sur nodes)    │                   │
│            └──────────────────────┘                   │
│                       │                                │
│                       ↓                                │
│         Lance EC2 instances (t3.medium)               │
│         Crée nouveaux nodes                           │
│                       │                                │
│                       ↓                                │
│         Nodes: 2 → 3 → 4 (ou plus)                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.1 — Ouvrir 2 Terminaux

Vous aurez besoin de **2 terminaux** pour observer les changements en temps réel :

- **Terminal A** : Lancer la charge et monitorer HPA
- **Terminal B** : Monitorer les nodes

### 3.2 — Terminal A : Lancer la Charge

```bash
# Déployer le générateur de charge
kubectl apply -f k8s/utils/load-generator.yaml

# Monitorer le HPA en temps réel (mise à jour chaque seconde)
watch -n 1 kubectl get hpa php-apache-hpa

# Pour plus de détails sur le HPA
watch -n 1 kubectl describe hpa php-apache-hpa
```

### 3.3 — Terminal B : Monitorer les Nodes

```bash
# Observer la création de nodes Karpenter
watch -n 2 kubectl get nodes -o wide

# OU pour plus de détails
watch -n 2 "echo '=== NODES ===' && kubectl get nodes && echo '=== KARPENTER STATUS ===' && kubectl get nodeclaims -o wide"
```

### 3.4 — Observations Attendues (Phase 1 : Scale UP)

Voici le **timeline typique** du scale-up :

| Temps | HPA Status | Pods | Nodes | Explication |
|-------|-----------|------|-------|-------------|
| T+0s | 1/1 Running | 1 | 2 (système) | État initial |
| T+15-30s | CPU détecté ↑ | 1 | 2 | Load-generator démarre, CPU monte |
| T+30-60s | CPU > 50% | 1 → 5-10 | 2 saturés | HPA détecte la charge, crée des pods |
| T+60-90s | 10 replicas | 10 (Pending) | 2 | Pods créés mais aucune place → Pending |
| T+90-120s | 10 replicas | 10 (+ Running) | 2 → 3+ | Karpenter crée nodes, pods se placent |
| T+120-180s | 10 replicas (stable) | 10 (Running) | 3+ (stable) | Équilibre trouvé |

### 3.5 — Interprétation des États

**`watch kubectl get hpa`** affichera quelque chose comme :

```
NAME               REFERENCE              TARGETS    MINPODS  MAXPODS  REPLICAS  AGE
php-apache-hpa     Deployment/php-apache  245%/50%   1        10       10        2m30s
```

| Champ | Signification |
|-------|---------------|
| `245%/50%` | CPU actuel à 245%, seuil à 50% → SCALE UP |
| `REPLICAS: 10` | 10 pods actuels (max atteint) |
| `MINPODS/MAXPODS: 1/10` | Configuration du HPA |

**`kubectl get pods`** affichera :

```
NAME                          READY   STATUS    RESTARTS   AGE
php-apache-57f89c4b4d-xxxxx   1/1     Running   0          50s
php-apache-57f89c4b4d-yyyyy   1/1     Running   0          45s
php-apache-57f89c4b4d-zzzzz   0/1     Pending   0          10s
... (7 pods au total, certains Pending)
```

**`kubectl get nodes`** affichera :

```
NAME                        STATUS   ROLES    AGE   VERSION
ip-10-0-1-10.ec2.internal  Ready    <none>   2h    v1.34.0
ip-10-0-1-11.ec2.internal  Ready    <none>   2h    v1.34.0
ip-10-0-1-100.ec2.internal Ready    <none>   1m    v1.34.0   ← Node Karpenter
ip-10-0-1-101.ec2.internal Ready    <none>   1m    v1.34.0   ← Node Karpenter
```

### 3.6 — Commandes Utiles Pendant le Test

```bash
# Voir les logs de Karpenter pour observer ses décisions
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 -f

# Voir les NodeClaims (demandes de nodes) créées par Karpenter
kubectl get nodeclaims -o wide

# Voir les pods Pending qui demandent des ressources
kubectl get pods --field-selector=status.phase=Pending

# Voir les événements du cluster
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Vérifier la charge CPU des nodes
kubectl top nodes

# Vérifier la consommation CPU des pods
kubectl top pods
```

---

## 📉 Étape 4 : Phase 2 - Scale DOWN (Arrêter et Observer la Consolidation)

Une fois que vous avez observé le scale-up pendant 2-3 minutes, arrêtez la charge pour voir Karpenter **consolider** les nodes.

### 4.1 — Arrêter le Générateur de Charge

**Dans Terminal A** :

```bash
# Arrêter le load-generator
kubectl delete -f k8s/utils/load-generator.yaml

# Monitorer le HPA réduire les replicas
watch -n 1 kubectl get hpa php-apache-hpa

# Vous verrez :
# - D'abord : HPA détecte CPU ↓, commence à réduire replicas
# - Puis : Les replicas diminuent graduellement (1-2 min)
# - Enfin : Retour à 1 replica (état initial)
```

### 4.2 — Monitorer la Consolidation Karpenter

**Dans Terminal B** :

```bash
# Observer les nodes disparaître progressivement
watch -n 3 kubectl get nodes -o wide

# Vous devriez voir :
# - Nodes Karpenter rester en Running (peut prendre 1-2 min)
# - Puis : Nœuds Karpenter progressivement supprimés
# - Finalement : Retour aux 2 nodes système
```

### 4.3 — Observations Attendues (Phase 2 : Scale DOWN)

| Temps | HPA Status | Pods | Nodes | Explication |
|-------|-----------|------|-------|-------------|
| T+0s | 10 replicas | 10 (Running) | 3+ | État avant arrêt |
| T+30-60s | CPU détecté ↓ | 10 → 5 | 3+ | Load arrêtée, CPU chute, HPA commence |
| T+60-120s | Réduction progressive | 5 → 2 | 3 | HPA continue à réduire replicas |
| T+120-180s | 1 replica (stable) | 1 | 3 | HPA terminé, pods réduits |
| T+180-240s | 1 replica (stable) | 1 | **2 (→1?)** | ✨ Karpenter **consolide**, supprime nodes vides |
| T+240s+ | 1 replica | 1 | 2 (système) | **Retour à l'état initial** ✅ |

### 4.4 — Comprendre la Consolidation

**Consolidation** = Karpenter supprime les nodes qui ne sont plus utiles :

1. ✋ **Les pods réduisent** → peu de charge CPU
2. 🔍 **Karpenter détecte** → nodes underutilisés ou vides
3. ⏱️ **Attente de 1 minute** (délai de consolidation par défaut)
4. 🔄 **Réschédule les pods** → les place sur les nodes existants
5. ❌ **Supprime les nodes vides** → termine les instances EC2

### 4.5 — Délais de Consolidation

⚠️ **Important** : La consolidation peut prendre du temps !

```
T=0min  : Vous arrêtez le load-generator
T=1-2min: HPA réduit les replicas
T=2-3min: Nodes Karpenter restent (attente de consolidation)
T=3-5min: Consolidation démarre
T=5-7min: Nodes supprimés progressivement
T=7min+ : Retour aux 2 nodes système
```

**Total attendu** : **5-7 minutes** pour un retour complet à l'état initial

---

## 🔍 Étape 5 : Vérifier l'État Final

Une fois la consolidation terminée, vérifiez que tout est revenu à l'état initial :

```bash
# Vérifier les nodes (devrait avoir 2 nodes système)
kubectl get nodes -L role

# Résultat attendu :
# NAME                        READY ROLES AGE    VERSION
# ip-10-0-1-10.ec2.internal   Ready <none> 2h    v1.34.0 (role=system)
# ip-10-0-1-11.ec2.internal   Ready <none> 2h    v1.34.0 (role=system)

# Vérifier les pods (devrait avoir 1 pod php-apache)
kubectl get pods -n default

# Résultat attendu :
# NAME                         READY STATUS  RESTARTS AGE
# php-apache-57f89c4b4d-xxxxx 1/1   Running 0        1m

# Vérifier le HPA (devrait afficher 1 replica)
kubectl get hpa php-apache-hpa

# Résultat attendu :
# NAME               REFERENCE              TARGETS  MINPODS MAXPODS REPLICAS AGE
# php-apache-hpa     Deployment/php-apache  0%/50%   1       10      1        3m
```

---

## 📊 Dashboard de Monitoring

Pour un monitoring plus visuel, vous pouvez utiliser des outils comme Kubernetes Dashboard ou Prometheus :

### Avec kubectl

```bash
# Top nodes (utilisation des ressources)
kubectl top nodes

# Top pods
kubectl top pods -A

# Détails du HPA
kubectl describe hpa php-apache-hpa

# Events du cluster (les actions de scaling)
kubectl get events -A --sort-by='.lastTimestamp'
```

### Avec Kubernetes Dashboard (optionnel)

```bash
# Déployer Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Créer un proxy local
kubectl proxy

# Accéder à : http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

---

## 🧹 Étape 6 : Nettoyage Après le Test

Après le test, vous pouvez :

### 6.1 — Garder l'Application Déployée

Si vous voulez continuer à tester, laissez l'application :

```bash
# L'application restera déployée pour d'autres tests
kubectl get deployment php-apache
```

### 6.2 — Restaurer l'État Initial (Pods Réduits)

```bash
# Supprimer le load-generator (s'il est encore actif)
kubectl delete -f k8s/utils/load-generator.yaml --ignore-not-found

# Attendre la réduction (1-2 minutes)
watch kubectl get hpa php-apache-hpa

# Attendre la consolidation Karpenter (2-3 minutes)
watch kubectl get nodes
```

### 6.3 — Supprimer Complètement l'Application

```bash
# Supprimer tous les objets Kubernetes
kubectl delete -k ./k8s/base

# Vérifier la suppression
kubectl get deployment php-apache  # Devrait ne rien retourner
kubectl get hpa                     # Devrait ne rien retourner
```

---

## 🆘 Dépannage

### Problème : HPA affiche `<unknown>` pour le CPU

**Cause** : metrics-server n'est pas prêt
**Solution** :

```bash
# Vérifier que metrics-server est Running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Attendre 2-3 minutes et réessayer
sleep 180
kubectl top pods
```

### Problème : Les pods ne scale pas au-delà de 1

**Cause** : CPU request non défini
**Cause possible** : Les pods n'utilisent pas assez de CPU
**Solution** :

```bash
# Vérifier les CPU requests
kubectl describe deployment php-apache | grep -A 3 "Limits\|Requests"

# Lancer manuellement un test de charge
kubectl run -it --rm load-tester --image=busybox /bin/sh
# À l'intérieur : while sleep 0.01; do wget -q -O- http://php-apache; done
```

### Problème : Karpenter crée trop de nodes

**Cause** : Configuration NodePool trop permissive
**Solution** :

```bash
# Vérifier la config NodePool
kubectl describe nodepool microservices-general-ondemand

# Vérifier les limites de CPU
kubectl get nodepool -o jsonpath='{.items[*].spec.limits.resources}'
```

### Problème : Nodes ne se suppriment pas après consolidation

**Cause** : Pods ne sont pas gracefully terminables
**Solution** :

```bash
# Vérifier les pods bloqués
kubectl get pods --all-namespaces --field-selector=status.phase=Pending

# Vérifier les logs Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i consolidat
```

---

## 📝 Notes Importantes

### Concernant les Délais

- ⏱️ **EC2 boot time** : ~60 secondes pour qu'une instance EC2 soit Ready
- ⏱️ **Pod scheduling** : ~10-30 secondes après que le node soit Ready
- ⏱️ **HPA metrics collection** : ~30-60 secondes pour collecter des métriques
- ⏱️ **Consolidation delay** : ~1 minute avant suppression des nodes vides
- ⏱️ **Total scale-up** : 2-5 minutes (HPA + Karpenter)
- ⏱️ **Total scale-down** : 5-10 minutes (HPA + Karpenter consolidation)

---

## Récapitulatif

### Objectif Global

Démontrer le **double-level autoscaling** :
1. **HPA (Horizontal Pod Autoscaler)** : Augmente/réduit le nombre de **pods** en fonction du CPU
2. **Karpenter** : Augmente/réduit le nombre de **nodes** en fonction des pods en attente

### Phases du Test

| Phase | Étape | Action | Durée | Résultat |
|-------|-------|--------|-------|----------|
| **Préparation** | 1-2 | Déployer app + vérifier métriques | <5 min | App running, metrics OK |
| **Scale UP** | 3 | Lancer load-generator | 2-3 min | Pods: 1→10, Nodes: 2→3+ |
| **Observation** | 3.6 | Monitorer avec watch/logs | 2 min | Voir les décisions Karpenter |
| **Scale DOWN** | 4 | Arrêter load-generator | 2-3 min | Pods: 10→1, Nodes: 3+→2 |
| **Vérification Finale** | 5 | Vérifier retour à l'état initial | <1 min | État initial confirmé |

### ✅ État Attendu à Chaque Étape

**Étape 1-2 (Préparation)** :
- ✅ 1 pod php-apache `Running`
- ✅ 2 nodes système en `Ready`
- ✅ HPA affichant `0%/50%`
- ✅ metrics-server en `Running`

**Étape 3 (Scale UP - après ~90-120s)** :
- ✅ HPA augmente replicas vers 10
- ✅ Pods en état `Pending` (pas assez de place)
- ✅ Karpenter détecte pods `Pending`
- ✅ **2-3 nodes Karpenter créés** (t3.medium on-demand)
- ✅ Pods se placent progressivement en `Running`
- ✅ HPA stabilise à 10 replicas

**Étape 4 (Scale DOWN - après arrêt du load)** :
- ✅ HPA détecte CPU ↓ après 1-2 min
- ✅ Replicas réduisent progressivement (10 → 5 → 1)
- ✅ Nodes Karpenter restent pendant 1 minute (consolidation delay)
- ✅ Karpenter **supprime les nodes vides** après consolidation
- ✅ Retour aux **2 nodes système** uniquement

**Étape 5 (Vérification)** :
- ✅ 1 pod php-apache `Running`
- ✅ 2 nodes système avec label `role=system`
- ✅ Aucun node Karpenter restant
- ✅ HPA affichant `0%/50%` (bas CPU)

### Flux d'Autoscaling Observé

```
┌─────────────────────────────────────────────────────────────┐
│                   PHASE SCALE UP                            │
└─────────────────────────────────────────────────────────────┘

Load-Generator activé
        ↓
Charge CPU augmente (50% seuil atteint)
        ↓
HPA détecte CPU > 50% (tous les 15s)
        ↓
Replicas : 1 → 2 → 5 → 10 (augmentation progressive)
        ↓
10 pods lancés, mais 2 nodes saturées
        ↓
Pods en état "Pending" (pas de place)
        ↓
Karpenter détecte pods Pending
        ↓
Crée 2-3 nodes EC2 (t3.medium, ~60s par node)
        ↓
Pods se placent sur nouveaux nodes
        ↓
Cluster stable : 10 pods Running + 3-4 nodes Ready

┌─────────────────────────────────────────────────────────────┐
│                   PHASE SCALE DOWN                          │
└─────────────────────────────────────────────────────────────┘

Load-Generator arrêté
        ↓
Charge CPU diminue progressivement
        ↓
HPA détecte CPU < 50% (après ~1-2 min)
        ↓
Replicas : 10 → 5 → 2 → 1 (réduction progressive)
        ↓
Moins de pods en Running
        ↓
Karpenter détecte nodes underutilisés/vides
        ↓
Attend 1 minute (consolidation delay par défaut)
        ↓
Réschédule les pods sur les nodes existants
        ↓
Supprime les nodes vides (termine instances EC2)
        ↓
Cluster retour état initial : 1 pod + 2 nodes système
```

### Métriques Clés à Observer

**Via `watch kubectl get hpa`** :
- `TARGETS` : CPU actuel / seuil (ex: `245%/50%`)
- `REPLICAS` : nombre actuel de pods

**Via `watch kubectl get nodes`** :
- Voir les nodes Karpenter apparaître et disparaître
- Vérifier le `READY` status

**Via `kubectl logs -n karpenter`** :
- Voir les décisions Karpenter en temps réel
- Chercher les messages "provision", "consolidate", etc.

### ✅ Vérifications Essentielles

**Si HPA montre `<unknown>` pour CPU** :
→ metrics-server n'est pas prêt, attendre 2-3 min

**Si pods ne scale pas au-delà de 1** :
→ Vérifier que la charge est bien générée et CPU > 50%

**Si Karpenter crée trop de nodes** :
→ Vérifier la configuration NodePool (limites de ressources)

**Si nodes ne se suppriment pas après scale-down** :
→ Vérifier les logs Karpenter pour `consolidat` ou pods bloqués

### Leçons Apprises du Test

1. **HPA + Karpenter = Orchestration complète** : Gestion automatique à 2 niveaux
2. **Timing est critique** : Délais d'EC2 boot, métriques, consolidation à comprendre
3. **Observation temps réel** : `watch`, `describe`, `logs` sont essentiels pour déboguer
4. **Consolidation ≠ Suppression immédiate** : Délais et conditions de consolidation importants
5. **Sécurité taints/tolerations** : System nodes restent isolés même pendant le stress

