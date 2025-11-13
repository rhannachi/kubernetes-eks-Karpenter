

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

---
---

## AWS EKS

### 0. Prérequis: 
https://github.com/rhannachi/kubernetes-aws-microservices/blob/main/README-aws-install-config.md

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

Nécessaire pour le HPA:
```shell
kubectl delete -f k8s/overlay/aws/metric-server.yaml
kubectl apply -f k8s/overlay/aws/metric-server.yaml
```

Vérifie :
```bash
kubectl top pods -A
kubectl top nodes
```
Si tu obtiens des métriques, tout est bon !

---

### Commandes pour créer le rôle IAM & l’annoter

#### 1. Créer le rôle IAM avec la trust policy :

- `<ACCOUNT_ID>` : ton ID de compte AWS (ex. 272391830312) (obtenu via: `aws sts get-caller-identity --query "Account" --output text`)
- `<REGION>` : ta région (ex. us‑east‑1)
- `<OIDC_PROVIDER_ID>` : l’ID OIDC de ton cluster (obtenu via: `aws eks describe-cluster --name microservices-demo-cluster --query "cluster.identity.oidc.issuer"` et récupération de la partie finale après /id/)

modifier `trust-policy.json`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_PROVIDER_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_PROVIDER_ID>:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_PROVIDER_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

```shell
aws iam create-role --role-name ClusterAutoscalerRole --assume-role-policy-document file://trust-policy.json
```

#### 2. Attacher la policy AWS recommandée (ou ta version personnalisée) :
```shell
aws iam create-policy --policy-name ClusterAutoscalerPolicy --policy-document file://cluster-autoscaler-policy.json
```
Note la valeur du champ "Arn" retourné (par ex. `arn:aws:iam::<ACCOUNT_ID>:policy/ClusterAutoscalerPolicy`).

* Attache cette policy à ton rôle (Remplace <ACCOUNT_ID> par ton ID AWS réel) :
```shell
aws iam attach-role-policy --role-name ClusterAutoscalerRole --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/ClusterAutoscalerPolicy
```

* Vérifie que la policy est bien attachée :
```shell
aws iam list-attached-role-policies --role-name ClusterAutoscalerRole
```
#### 3. Cluster Autoscaler
```shell
kubectl apply -f k8s/overlay/aws/cluster-autoscaler.yaml
```

#### 4. Annoter le ServiceAccount Kubernetes :
```shell
kubectl annotate serviceaccount cluster-autoscaler -n kube-system eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/ClusterAutoscalerRole
```
---

### 3. php-apache

```shell
kubectl apply -k ./k8s/overlay/aws

kubectl -n kube-system get pods | grep autoscaler
kubectl logs -n kube-system deployment/cluster-autoscaler
```

---

### 4. Générateur de charge (load-generator)

```
kubectl apply -f ./utils/load-generator.yaml
```

---

### 5. Vérifier le scaling en temps réel

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

### 6. Nettoyage

```bash
kubectl delete -f load-generator.yaml
kubectl delete -k ./k8s/overlay/aws
eksctl delete cluster -f ./infra/cluster.yaml
```