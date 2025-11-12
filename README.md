

## Minikube

Assure-toi que Minikube est démarré :
```bash
minikube start
```

Active le **metrics-server** (indispensable pour le HPA) :
```bash
minikube addons enable metrics-server
```

Vérifie son bon fonctionnement :
```bash
kubectl top nodes
kubectl top pods
```

Applique le déploiement :
```shell
kubectl kustomize ./k8s/overlay/minikube
kubectl apply -k ./k8s/overlay/minikube
```

