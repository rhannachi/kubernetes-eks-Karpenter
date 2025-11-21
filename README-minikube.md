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
```bash
kubectl run -it --rm load-generator --image=busybox /bin/sh
```

Puis dans le shell du pod :
```bash
# Boucle infinie envoyant des requêtes HTTP au service interne
while true; do wget -q -O- http://php-apache; done
```

Laisse tourner pendant 2-3 minutes

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

Reviens sur le pod `load-generator` et fais `Ctrl+C`.

Puis quitte le shell :

```bash
exit
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
kubectl delete -k -k ./k8s/overlay/minikube
```

