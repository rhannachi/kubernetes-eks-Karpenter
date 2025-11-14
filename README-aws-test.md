# Test Charge eks karpenter

### Dashboard Admin Surveillance
```shell
# ServiceAccount et les permissions
kubectl apply -f k8s/utils/dashboard-admin.yaml

# Créer le token d'accès
kubectl -n kubernetes-dashboard create token admin-user
# Copiez le token généré (il ressemble à : eyJhbGciOiJSUzI1NiIsImtpZCI6I...)

# Installer le dashboard Kubernetes
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

#  Lancer le prox
kubectl proxy

# Accéder au Dashboard
# http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```


### Surveiller Karpenter
```shell
# Terminal 1 : Surveiller les nœuds
watch kubectl get nodes

# Terminal 2 : Surveiller les NodeClaims (créés par Karpenter)
watch kubectl get nodeclaim

# Terminal 3 : Surveiller les logs Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

### Déployer le test
```shell
kubectl apply -f k8s/utils/test-karpenter-scaling.yaml
```

### Scaler progressivement

```shell
# Commencer avec 5 replicas (devrait tenir sur vos nœuds existants)
kubectl scale deployment inflate --replicas=5
kubectl get pods -w

# Vérifier la capacité actuelle
kubectl top nodes

# Augmenter à 10 replicas
kubectl scale deployment inflate --replicas=10


```






















