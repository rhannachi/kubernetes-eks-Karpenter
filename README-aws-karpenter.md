# installation de Karpenter

## ✅ ÉTAPE 1 : Créer les rôles IAM (une seule fois)

```shell script
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Créer le Service Account avec les permissions
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --name=karpenter \
  --namespace=kube-system \
  --attach-policy-arn=arn:aws:iam::aws:policy/AdministratorAccess \
  --approve \
  --override-existing-serviceaccounts

# 2. Créer le rôle pour les nodes Karpenter
aws iam create-role \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --assume-role-policy-document file://infra/karpenter-node-trust-policy.json

aws iam attach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME}
aws iam add-role-to-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} --role-name KarpenterNodeRole-${CLUSTER_NAME}

# 3. Tagger les sous-réseaux et security groups
export NODEGROUP=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'nodegroups[0]' --output text)
export LAUNCH_TEMPLATE=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${NODEGROUP} --region ${AWS_REGION} --query 'nodegroup.launchTemplate.id' --output text)

aws ec2 describe-subnets --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" --query 'Subnets[*].SubnetId' --output text | tr '\t' '\n' | while read subnet; do
  aws ec2 create-tags --resources $subnet --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
done

aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text | xargs -I {} aws ec2 create-tags --resources {} --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
```

### Script de vérification de l'ÉTAPE 1
```shell
./verify-step1.sh
```

---

## étape 2. Karpenter via Helm

```shell
# 1. Récupérer l'endpoint du cluster et mettre à jour karpenter.yaml
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region : ${AWS_REGION}"
echo "aws account id : ${AWS_ACCOUNT_ID}"

export CLUSTER_ENDPOINT=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.endpoint" --output text)
echo "Votre endpoint : $CLUSTER_ENDPOINT"

# Extraire l'ARN du rôle
export KARPENTER_IAM_ROLE_ARN=$(kubectl get sa karpenter -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "IAM Role ARN: ${KARPENTER_IAM_ROLE_ARN}"

# Récupérer le nom du rôle
export KARPENTER_ROLE_NAME=$(kubectl get sa karpenter -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | cut -d'/' -f2)
echo "nom du rôle ${KARPENTER_ROLE_NAME}"
```

### installer Karpenter via Helm

```shell
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.8.2 \
  --namespace karpenter \
  --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set controller.resources.requests.cpu=500m \
  --set controller.resources.requests.memory=512Mi \
  --wait
```

### Vérification de l'installation de karpenter via Helm
```shell
# Vérifier que les pods Karpenter sont en running
kubectl get pods -n karpenter

# Vérifier les CRDs Karpenter
kubectl get crd | grep karpenter

# Voir les logs de Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

### Déployer le NodePool Karpenter

```shell
# Récupérer l'AMI utilisée par vos nœuds actuels
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=microservices-demo-cluster" \
  --region us-east-1 \
  --query 'Reservations[*].Instances[*].[ImageId]' \
  --output text | head -1
```

> Une fois que vous avez l'AMI ID, mettez à jour votre fichier `infra/karpenter-nodepool.yaml` :
```yaml
...
spec:
  role: "KarpenterNodeRole-microservices-demo-cluster"
  amiFamily: AL2
  amiSelectorTerms:
    - id: "ami-xxxxxxxxx"  # Remplacez par l'AMI ID réelle
...
```

```shell
kubectl apply -f infra/karpenter-nodepool.yaml
```

Vérifier le status du NodePool:
```shell
kubectl get ec2nodeclass default -o jsonpath='{.status.conditions[?(@.type=="AMIsReady")]}' | jq
kubectl get nodepool
kubectl describe nodepool default
```

---

## Déployer votre application php-apache & load generator 

```shell
kubectl apply -k ./k8s/base
kubectl apply -f ./k8s/utils/load-generator.yaml
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

---

## Clean UP !

```shell
#!/bin/bash
CLUSTER_NAME="microservices-demo-cluster"
AWS_REGION="us-east-1"

echo "🗑️  Suppression du cluster EKS..."
eksctl delete cluster -f ./infra/cluster.yaml --wait

echo "🗑️  Nettoyage des ressources IAM Karpenter..."
aws iam remove-role-from-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} --role-name KarpenterNodeRole-${CLUSTER_NAME} 2>/dev/null
aws iam delete-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} 2>/dev/null
aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null
aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null
aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null
aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null
aws iam delete-role --role-name KarpenterNodeRole-${CLUSTER_NAME} 2>/dev/null

echo "✅ Tout est supprimé !"
```

