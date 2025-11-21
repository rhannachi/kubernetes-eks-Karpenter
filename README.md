# Installation et configuration de Karpenter avec Helm sur un cluster EKS AWS

Avant de passer à la mise en place d’un HPA avec un auto-scaling automatisé grâce à Karpenter sur un cluster EKS AWS, vous pouvez tester un HPA sur Minikube
[README-minikube.md](README-minikube.md)

## étape 1 - Installation AWS CLI, eksctl et configuration d'un utilisateur AWS
[README-aws-user.md](README-aws-user.md)

## étape 2 - Création cluster AWS EKS
[README-aws-cluster.md](README-aws-cluster.md)

## étape 3 - Installation de Karpenter EKS AWS
[README-aws-karpenter.md](README-aws-karpenter.md)

---

## étape 4 - Déployer votre application php-apache et tester karpenter autoscaling

```shell
kubectl apply -k ./k8s/base
```

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

Pour générer de la charge et observer Karpenter en action :

1. Ouvrez un terminal pour générer de la charge :
```shell
kubectl run -it --rm load-generator --image=busybox /bin/sh
```

2. Dans le shell du load-generator, exécutez :
```shell
while true; do wget -q -O- http://php-apache; done
```

3. Dans un autre terminal, observez le scaling :
```shell
# Surveiller les pods
watch kubectl get pods

# Surveiller les noeuds Karpenter
watch kubectl get nodes
```

#### Points clés à observer

- Karpenter va automatiquement provisionner de nouveaux noeuds à mesure que la charge augmente
- Le HPA va augmenter le nombre de réplicas jusqu'à 10
- Les nouveaux noeuds seront de type t3.medium ou t3.large selon la configuration Karpenter

`★ Insight ─────────────────────────────────────`
- Le scaling avec Karpenter est dynamique et répond rapidement aux besoins de charge
- Les ressources sont provisionnées de manière optimale, minimisant les ressources inutilisées
`─────────────────────────────────────────────────`

### Nettoyage

Pour arrêter le générateur de charge et restaurer l'état initial :
```shell
# Terminer le load-generator
kubectl delete pod load-generator

# Attendre que Karpenter récupère les noeuds surnuméraires
```

