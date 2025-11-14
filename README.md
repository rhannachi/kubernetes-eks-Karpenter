

## étape 1
[README-aws-user.md](README-aws-user.md)

## étape 2
[README-aws-cluster.md](README-aws-cluster.md)

## étape 3
[README-aws-karpenter.md](README-aws-karpenter.md)

---

---

## Déployer votre application php-apache & load generator

```shell
kubectl apply -k ./k8s/base
kubectl apply -f ./k8s/utils/test-minikube-scaling.yaml
```

## Observer Karpenter en action

```shell
# Voir les pods Karpenter réagir
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Dans un autre terminal, surveiller les nœuds
watch kubectl get nodes

# Surveiller le HPA
kubectl get hpa -w

# Surveiller les pods
kubectl get pods -w
```


