# Création cluster AWS EKS

## Vue d'ensemble

Ce cluster EKS est configuré pour utiliser **Karpenter** comme solution de scaling automatique. Il contient :
- ✅ 2 nodes système statiques (pour Karpenter, metrics-server, coredns, etc.)
- ✅ OIDC activé pour les service accounts IAM
- ✅ Tags pour la découverte automatique par Karpenter
- ✅ Taints sur les nodes système pour éviter que les workloads applicatifs s'y déploient

---

## 1. Création du cluster Kubernetes

### Créer le cluster EKS

Le fichier [cluster.yaml](infra/cluster.yaml) définit :
- **Node group système** : 2 nodes t3.medium fixes (pas d'autoscaling)
- **Taints** : Les nodes système ont un taint `CriticalAddonsOnly` pour réserver leur capacité aux services critiques
- **Tags Karpenter** : Tag `karpenter.sh/discovery` pour que Karpenter découvre le VPC et les security groups
- **OIDC** : Activé pour permettre à Karpenter d'assumer un rôle IAM

```bash
eksctl create cluster -f ./infra/cluster.yaml
```

Temps d'attente estimé : 15-20 minutes

### Vérifier que les nœuds sont opérationnels

```bash
kubectl get nodes
```

Tu devrais voir 2 nœuds en `Ready` avec le label `role=system` :

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-x-x.ec2.internal      Ready    <none>   5m    v1.34.x
ip-10-0-y-y.ec2.internal      Ready    <none>   5m    v1.34.x
```

Vérifier les labels et taints :

```bash
kubectl get nodes --show-labels
kubectl describe nodes | grep -A 5 Taints
```

Tu devrais voir :
- Labels : `role=system`, `workload-type=system`
- Taints : `CriticalAddonsOnly=true:NoSchedule`

### Vérifier la configuration du cluster

```bash
# Vérifier que OIDC est bien activé
aws eks describe-cluster --name microservices-demo-cluster --region us-east-1 \
  --query "cluster.identity.oidc.issuer" --output text

# Vérifier les add-ons installés
kubectl get pods -n kube-system
```

---

## 2. Déploiement du metrics-server

Le metrics-server est **essentiel** pour :
- ✅ Le HPA (Horizontal Pod Autoscaler) qui scale les pods
- ✅ Les commandes `kubectl top pods` et `kubectl top nodes`
- ✅ Karpenter qui utilise les métriques pour ses décisions de scaling

### Attendre que le metrics-server se déploie

EKS peut déployer automatiquement le metrics-server. Vérifie d'abord s'il existe :

```bash
kubectl get deployment metrics-server -n kube-system
```

**Si le metrics-server existe déjà** :
```bash
# Supprimer la version par défaut
kubectl delete deployment metrics-server -n kube-system
kubectl delete service metrics-server -n kube-system
```

### Déployer notre configuration personnalisée

Notre configuration inclut les paramètres nécessaires pour EKS [metric-server.yaml](infra/metric-server.yaml):

```bash
kubectl apply -f infra/metric-server.yaml
```

### Vérifier le déploiement

```bash
# Vérifier que le pod est en running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Attendre que le pod soit prêt (peut prendre 1-2 minutes)
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s
```

### Tester que les métriques fonctionnent

```bash
# Voir les métriques des nodes
kubectl top nodes

# Voir les métriques des pods
kubectl top pods -A
```

Si tu obtiens des métriques (et pas d'erreur), tout est bon ! ✅

**Note** : Si tu as une erreur `Metrics API not available`, attends 2-3 minutes que le metrics-server se stabilise.

---

## Récapitulatif
TODO