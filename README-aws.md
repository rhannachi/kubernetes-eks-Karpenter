
## AWS EKS

### 1. Création du cluster Kubernetes

Créer un cluster EKS en utilisant un fichier de configuration `cluster.yaml` :
```bash
eksctl create cluster -f ./infra/cluster.yaml
```
Ce fichier définit le nombre de nœuds, le type d’instance, le VPC, les sous-réseaux et d’autres paramètres du cluster.

Vérifie que les nœuds sont opérationnels :
```bash
kubectl get nodes
```
Tu devrais voir tous les nœuds du cluster en `Ready`.

---

### 2. Déploiement du metrics-server

avant de passer a cette étape , on doit attendre que les objets kubernetes en relation avec `metrics-server` ce créent avec succée.
```shell
kubectl get all -n kube-system | grep metrics-server
```
puis on les supprime et on les recrée avec notre propre config `k8s/overlay/aws/metric-server.yaml`

Nécessaire pour le HPA:
```shell
kubectl delete -f k8s/overlay/aws/metric-server.yaml
kubectl apply -f k8s/overlay/aws/metric-server.yaml
```

Vérifie :
```shell
kubectl get all -n kube-system | grep metrics-server
```

```bash
kubectl top pods -A
kubectl top nodes
```
Si tu obtiens des métriques, tout est bon !

---

### 3. TODO Karpenter 


---

### 4. php-apache

```shell
kubectl apply -k ./k8s/overlay/aws
```

---

### 5. Générateur de charge (load-generator)

```
kubectl apply -f ./utils/load-generator.yaml
```

---

### 6. Vérifier le scaling en temps réel

Surveille le HPA :

```bash
kubectl get hpa -w
```

Tu verras le scaling monter :

```
NAME             REFERENCE               TARGETS   MINPODS   MAXPODS   REPLICAS
php-apache-hpa   Deployment/php-apache   200%/50%   1         10        5
```

Et côté pods :

```bash
kubectl get pods -l app=php-apache -w
```

Si la charge est trop forte pour 2 nœuds EC2, le **Cluster Autoscaler** ajoutera automatiquement des nœuds :

```bash
kubectl get nodes
```

---

### 7. Nettoyage

```bash
kubectl delete -f load-generator.yaml
kubectl delete -k ./k8s/overlay/aws
eksctl delete cluster -f ./infra/cluster.yaml
```

