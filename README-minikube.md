## Test de charge du Horizontal Pod Autoscaler (HPA) sur un cluster minikube

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
* [deployment.yaml](k8s/base/deployment.yaml)
* [hpa.yaml](k8s/base/hpa.yaml)
```shell
kubectl kustomize ./k8s/overlay/minikube
kubectl apply -k ./k8s/overlay/minikube
```

👉 Cela veut dire :

* Minimum 1 pod
* Maximum 10 pods
* Si la moyenne CPU > 50% du **request (200m)** → scaling up

---

### Générer de la charge CPU

On va utiliser un pod temporaire pour faire des requêtes en boucle sur le service :

[load-generator.yaml](k8s/utils/load-generator.yaml)

```bash
kubectl apply -f k8s/utils/load-generator.yaml
```

Pour surveiller les logs du générateur de charge :
```bash
kubectl logs load-generator -f
```

---

### Observer le scaling

Dans un autre terminal :
```bash
kubectl get hpa -w
```

Après environ 1 à 2 minutes (temps de collecte du metrics-server),
tu devrais voir les valeurs évoluer :

```
NAME             REFERENCE               TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
php-apache-hpa   Deployment/php-apache   90%/50%   1         10        3          3m
php-apache-hpa   Deployment/php-apache   210%/50%  1         10        5          4m
```

Et en parallèle :
```bash
kubectl get pods -l app=php-apache
```

Tu verras plusieurs pods créés automatiquement

---

### Arrêter la charge

Pour arrêter et nettoyer :
```bash
kubectl delete -f k8s/utils/load-generator.yaml
```

Tu verras alors le nombre de pods redescendre progressivement :
```bash
kubectl get hpa -w
```

Exemple :
```
php-apache-hpa   Deployment/php-apache   20%/50%   1         10        2   10m
php-apache-hpa   Deployment/php-apache   10%/50%   1         10        1   12m
```

---

### Nettoyage

```bash
kubectl delete -k ./k8s/overlay/minikube
```