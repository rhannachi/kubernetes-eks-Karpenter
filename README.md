# Installation et configuration de Karpenter avec Helm sur un cluster EKS AWS

Avant de passer à la mise en place d'un HPA avec un auto-scaling automatisé grâce à Karpenter sur un cluster EKS AWS, vous pouvez tester un HPA sur Minikube
[README-minikube.md](README-minikube.md)

## étape 1 - Installation AWS CLI, eksctl et configuration d'un utilisateur AWS
[README-aws-user.md](README-aws-user.md)

## étape 2 - Création cluster AWS EKS
[README-aws-cluster.md](README-aws-cluster.md)

## étape 3 - Installation de Karpenter EKS AWS
[README-aws-karpenter.md](README-aws-karpenter.md)

---

## étape 4 - Déployer votre application php-apache et tester karpenter autoscaling

### Déploiement de l'application PHP-Apache

Cette application de démonstration utilise un Horizontal Pod Autoscaler (HPA) pour tester l'autoscaling de Karpenter. L'application est configurée avec les caractéristiques suivantes :
- Déploiement initial : 1 réplique
- Limite de répliques : 10 réplicas maximum
- Seuil de scaling : Scale-up si l'utilisation CPU dépasse 50%

#### Étapes de déploiement

1. Déployer l'application et le HPA :
```shell
kubectl apply -k ./k8s/base
```

2. Vérifier le déploiement initial :
```shell
kubectl get deployment php-apache
kubectl get hpa php-apache-hpa
```

### Tester l'autoscaling avec Karpenter

Ce test démontre le **scaling automatique** en deux niveaux :
- **HPA** : Scale les **pods** en réaction à la charge CPU
- **Karpenter** : Scale les **nodes EC2** en réaction aux pods qui ne tiennent plus

#### ⚙️ Vérifications initiales

Avant de commencer, assurez-vous que :

```shell
# 1. metrics-server est actif (REQUIS pour HPA - mesure du CPU)
kubectl get pods -n kube-system -l k8s-app=metrics-server

# 2. État initial : voir les nodes et pods actuels
kubectl get nodes
kubectl get pods
kubectl get hpa php-apache-hpa
```

*Vous devriez voir 2 nodes système et 1 pod php-apache initial.*

#### 🚀 Phase 1 : Scale-UP - Déclencher la charge et observer

Ouvrez **2 terminaux** pour voir le scaling en action :

**Terminal A : Lancer la charge et monitorer HPA**
```shell
# Déployer le générateur de charge
kubectl apply -f k8s/utils/load-generator.yaml

# Monitorer HPA : voir comment il scale les pods de 1 à 10
watch -n 1 kubectl get hpa php-apache-hpa
```

**Terminal B : Monitorer les NODES pour voir Karpenter en action**
```shell
# Voir les nodes existants et les nouveaux nodes créés par Karpenter
watch -n 2 kubectl get nodes -o wide
```

**Qu'observez-vous ?**

| Temps | HPA | Nodes | Explication |
|-------|-----|-------|-------------|
| T+0-30s | 1 replica → ↑ CPU détecté | 2 nodes | Load-generator démarre, CPU monte |
| T+30-60s | 1 → 10 replicas | 2 nodes saturés | HPA scale les pods (80% du seuil 50% × ~2 pods) |
| T+60-120s | 10 replicas | 2 → 3+ nodes | **Karpenter détecte les pods Pending** → crée des nodes EC2 |
| T+120-180s | 10 replicas (stable) | 3+ nodes | Nouveaux pods Running sur les nodes Karpenter |

**Pourquoi ça fonctionne ensemble ?**

1. **HPA** voit la CPU augmenter → ajoute des pods (jusqu'à 10 max)
2. Les 2 nodes système ne peuvent pas accueillir 10 pods → **pods Pending**
3. **Karpenter** détecte les pods Pending → **lance des instances EC2** t3.medium
4. Une fois que le node rejoint → les pods Pending changent en Running

#### 📉 Phase 2 : Scale-DOWN - Arrêter et observer la consolidation

Observez le processus inverse (réduction) :

**Terminal A : Arrêter la charge et monitorer HPA**
```shell
# Arrêter le load-generator
kubectl delete -f k8s/utils/load-generator.yaml

# Voir HPA réduire les replicas (va prendre 1-2 minutes)
watch -n 1 kubectl get hpa php-apache-hpa
```

**Terminal B : Monitorer la suppression des nodes Karpenter**
```shell
# Voir les nodes disparaître progressivement (1-3 minutes après arrêt)
watch -n 3 kubectl get nodes
```

**Qu'observez-vous ?**

| Temps | HPA | Nodes | Explication |
|-------|-----|-------|-------------|
| T+0-60s | 10 replicas → ↓ CPU chute | 3+ nodes | Load-generator arrêté, charge disparaît |
| T+60-120s | 10 → 1 replica | 3 nodes | HPA réduit les pods, nodes underutilisés |
| T+120-180s | 1 replica (stable) | **3 → 2 nodes** | **Karpenter consolide** → supprime les nodes vides |
| T+180s+ | 1 replica | **2 nodes** (système) | **Retour à l'état initial** ✅ |

**Pourquoi Karpenter supprime les nodes ?**

1. Les pods réduisent → peu de load CPU
2. Nodes Karpenter sont **vides ou underutilisés**
3. **Karpenter consolide** (1 minute d'attente par défaut)
4. Réschédule les pods sur les nodes existants
5. **Supprime les nodes vides** et termine les instances EC2

#### 📊 Résumé des délais attendus

| Étape | Délai | Signe de succès |
|-------|-------|-----------------|
| HPA détecte CPU ↑ | 30s | `watch kubectl get hpa` montre replicas augmenter |
| Pods scale 1 → 10 | 30-60s | `kubectl get pods` montre 10 pods (certains Pending) |
| Karpenter crée nodes | 60-120s | `kubectl get nodes` montre +1 ou +2 nodes supplémentaires |
| HPA scale 10 → 1 | 60-120s | `watch kubectl get hpa` après suppression load-generator |
| Karpenter consolide | 180-240s | `kubectl get nodes` revient à 2 nodes |

**Points clés :**
- ⏱️ **Patienter** : Chaque étape a des délais naturels (EC2 boot ~60s, consolidation ~1-2min)
- 👀 **Observer avec `watch`** : Les commandes `watch` vous montrent le changement en direct
- 💡 **HPA et Karpenter travaillent ensemble** : HPA scale les pods → Karpenter ajoute des nodes

### 🧹 Nettoyage - Restaurer l'état initial

Après le test, restaurez votre cluster à l'état initial :

```shell
# 1. Supprimer le load-generator (s'il est encore actif)
kubectl delete -f k8s/utils/load-generator.yaml --ignore-not-found

# 2. Vérifier que les pods php-apache sont réduits
# Le HPA devrait avoir scaling down vers 1 replica
kubectl get hpa php-apache-hpa
kubectl get pods -n default

# 3. IMPORTANT: Attendre la consolidation Karpenter
# Cela peut prendre jusqu'à 2-3 minutes selon votre NodePool consolidation TTL
# Les nodes provisionnés par Karpenter vont être progressivement SUPPRIMÉS
echo "Attendre la consolidation Karpenter (2-3 minutes)..."
watch kubectl get nodes

# 4. Vérifier que vous êtes revenu aux 2 nodes système initiaux
kubectl get nodes
# Vous devez voir : 2 nodes (system nodes) + 0 nodes Karpenter

# 5. Optionnel : Nettoyer complètement l'application (si vous n'en avez plus besoin)
# kubectl delete -k ./k8s/base
```

**Important à noter :**
- Les **nodes EC2 provisionnés par Karpenter** sont automatiquement supprimés après la consolidation
- Les **2 nodes système initiaux** restent (ils ont le taint `CriticalAddonsOnly=true:NoSchedule`)
- Karpenter peut prendre jusqu'à **1-2 minutes** de plus après la suppression du load-generator pour commencer la consolidation
- Si vous avez des pods "non-gracefully terminables", le scale-down peut être plus lent