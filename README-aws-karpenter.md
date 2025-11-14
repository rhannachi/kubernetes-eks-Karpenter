# Installation de Karpenter

## ✅ ÉTAPE 1 : Créer les rôles IAM et la policy sécurisée pour Karpenter

### 1.1 — Définir les variables d'environnement

```bash
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account: ${AWS_ACCOUNT_ID}"
```

### 1.2 — Créer la policy IAM personnalisée pour Karpenter

> ⚠️ **IMPORTANT** : Cette étape doit être effectuée via la **Console AWS** avec un compte administrateur, car l'utilisateur `eks-user` n'a pas la permission `iam:CreatePolicy`.

⚠️ **IMPORTANT** : Ne jamais utiliser `AdministratorAccess` pour Karpenter ! Créons une policy avec uniquement les permissions nécessaires.

#### 1 — Préparer le fichier de policy

Sur ton poste local, crée le fichier `infra/karpenter-controller-policy.json` avec les variables remplacées :

```bash
cat > infra/karpenter-controller-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowScopedEC2InstanceActions",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:launch-template/*",
        "arn:aws:ec2:*:*:security-group/*",
        "arn:aws:ec2:*:*:subnet/*",
        "arn:aws:ec2:*:*:network-interface/*",
        "arn:aws:ec2:*::image/*"
      ]
    },
    {
      "Sid": "AllowEC2InstanceActionsWithTags",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:spot-instances-request/*",
        "arn:aws:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${AWS_REGION}"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowEC2Actions",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeImages",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeSpotPriceHistory",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSSMReadActions",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
    },
    {
      "Sid": "AllowPricingReadActions",
      "Effect": "Allow",
      "Action": "pricing:GetProducts",
      "Resource": "*"
    },
    {
      "Sid": "AllowInterruptionQueueActions",
      "Effect": "Allow",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:Karpenter-${CLUSTER_NAME}"
    },
    {
      "Sid": "AllowPassingInstanceRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
    },
    {
      "Sid": "AllowEKSClusterAccess",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster"
      ],
      "Resource": "arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}"
    },
    {
      "Sid": "AllowIAMInstanceProfileActions",
      "Effect": "Allow",
      "Action": [
        "iam:ListInstanceProfiles",
        "iam:GetInstanceProfile"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

Remplace les variables dans le fichier :

```bash
sed -i "s/\${AWS_REGION}/${AWS_REGION}/g" infra/karpenter-controller-policy.json
sed -i "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" infra/karpenter-controller-policy.json
sed -i "s/\${CLUSTER_NAME}/${CLUSTER_NAME}/g" infra/karpenter-controller-policy.json
```

#### 2 — Créer la policy dans AWS via la Console

1. Connecte-toi à https://console.aws.amazon.com avec un compte **administrateur**
2. Va dans **IAM** → **Policies** → **Create policy**
3. Clique sur l'onglet **JSON**
4. Copie-colle le contenu du fichier `infra/karpenter-controller-policy.json` dans l'éditeur
5. Clique sur **Next**
6. Nom de la policy : `KarpenterControllerPolicy-microservices-demo-cluster`
7. Description : `IAM policy for Karpenter controller`
8. Clique sur **Create policy**

#### 3 — Vérifier que la policy est créée

Depuis ton terminal avec l'utilisateur `eks-user`, vérifie que la policy existe :

```bash
aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}
```

### 1.3 — Créer le Service Account IAM pour Karpenter

> 💡 **NOTE** : Le service account est créé directement dans le namespace `karpenter` (même namespace où Karpenter sera installé). Cela évite les problèmes de trust policy.

```bash
# Créer le namespace karpenter en premier
kubectl create namespace karpenter

# Créer le service account IAM dans le namespace karpenter
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --name=karpenter \
  --namespace=karpenter \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME} \
  --approve \
  --override-existing-serviceaccounts

```

### 1.4 — Créer le rôle IAM pour les nodes Karpenter

Ce rôle sera utilisé par les instances EC2 créées par Karpenter.

#### 1 — Vérifier si le rôle existe déjà

```bash
# Vérifier si le rôle existe
aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME} 2>/dev/null
```

**Si le rôle existe déjà** : Vérifiez qu'il a toutes les policies nécessaires avec :

```bash
aws iam list-attached-role-policies --role-name KarpenterNodeRole-${CLUSTER_NAME}
```

Vous devriez voir ces 4 policies :
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- AmazonSSMManagedInstanceCore

Vérifiez aussi l'instance profile :

```bash
aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME}
```

Si tout est correct, **passez directement à l'étape 1.5**. Sinon, continuez ci-dessous.

#### 2 — Créer le rôle (si nécessaire)

```bash
# Créer le rôle avec la trust policy
aws iam create-role \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --assume-role-policy-document file://infra/karpenter-node-trust-policy.json

# Attacher les policies nécessaires
aws iam attach-role-policy \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Créer l'instance profile
aws iam create-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME}

aws iam add-role-to-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --role-name KarpenterNodeRole-${CLUSTER_NAME}
```

#### 3 — Vérifier la configuration finale

```bash
# Vérifier que l'instance profile contient le bon rôle
aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --query 'InstanceProfile.Roles[0].RoleName' --output text
```

Le résultat doit être : `KarpenterNodeRole-microservices-demo-cluster`

### 1.5 — Tagger les sous-réseaux et security groups pour la découverte Karpenter

Karpenter utilise ces tags pour découvrir automatiquement les ressources réseau.

```bash
# Tagger tous les sous-réseaux du cluster
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
  --query 'Subnets[*].SubnetId' \
  --output text | tr '\t' '\n' | while read subnet; do
    aws ec2 create-tags \
      --resources $subnet \
      --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
    echo "Tagged subnet: $subnet"
done

# Tagger le security group du cluster
aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text | xargs -I {} aws ec2 create-tags \
    --resources {} \
    --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
```

### 1.6 — Vérification de l'ÉTAPE 1

Vérifie que tout est bien configuré avec le script de vérification :

```bash
./verify-step1.sh
```

Ou vérifie manuellement :

```bash
# Vérifier le service account
kubectl get sa karpenter -n karpenter -o yaml

# Vérifier l'annotation IAM
kubectl get sa karpenter -n karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Vérifier le rôle des nodes
aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME}

# Vérifier les tags des sous-réseaux
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## ✅ ÉTAPE 2 : Installer Karpenter via Helm

### 2.1 — Récupérer les informations du cluster

```bash
# Si tu n'as pas encore exporté ces variables
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Récupérer l'endpoint du cluster
export CLUSTER_ENDPOINT=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.endpoint" \
  --output text)

# Récupérer l'ARN du rôle IAM du service account
export KARPENTER_IAM_ROLE_ARN=$(kubectl get sa karpenter -n kube-system \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account ID: ${AWS_ACCOUNT_ID}"
echo "Cluster Endpoint: ${CLUSTER_ENDPOINT}"
echo "Karpenter IAM Role ARN: ${KARPENTER_IAM_ROLE_ARN}"
```

### 2.2 — Installer Karpenter via Helm

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.8.2 \
  --namespace karpenter \
  --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set controller.resources.requests.cpu=500m \
  --set controller.resources.requests.memory=512Mi \
  --set tolerations[0].key=CriticalAddonsOnly \
  --set tolerations[0].operator=Exists \
  --set tolerations[0].effect=NoSchedule \
  --wait
```

**Note** : Le toleration permet à Karpenter de s'exécuter sur les nodes système qui ont le taint `CriticalAddonsOnly`.

### 2.3 — Vérifier l'installation de Karpenter

```bash
# Vérifier que les pods Karpenter sont en running
kubectl get pods -n karpenter

# Tu devrais voir 2 pods en Running
# NAME                          READY   STATUS    RESTARTS   AGE
# karpenter-xxxxxxxxxx-xxxxx    1/1     Running   0          2m
# karpenter-xxxxxxxxxx-xxxxx    1/1     Running   0          2m
```

Vérifier les CRDs Karpenter :

```bash
kubectl get crd | grep karpenter
```

Tu devrais voir :
```
ec2nodeclasses.karpenter.k8s.aws
nodeclaims.karpenter.sh
nodepools.karpenter.sh
```

Vérifier les logs de Karpenter (ne devrait plus contenir d'erreurs `AccessDenied`) :

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50
```

Les logs doivent afficher uniquement des messages `INFO` sur les contrôleurs qui démarrent. Si tu vois encore des erreurs `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity`, vérifie que tu as bien mis à jour le trust policy à l'étape 2.3.

---

## ✅ ÉTAPE 3 : Déployer le NodePool et EC2NodeClass Karpenter

### 3.1 — Récupérer l'AMI utilisée par les nœuds actuels

Karpenter a besoin de connaître l'AMI à utiliser pour les nouveaux nodes :

```bash
# Récupérer l'AMI des nœuds actuels
AMI_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --region ${AWS_REGION} \
  --query 'Reservations[*].Instances[*].[ImageId]' \
  --output text | head -1)

echo "AMI ID: ${AMI_ID}"
```

**Alternative** : Récupérer l'AMI optimisée EKS automatiquement :

```bash
# Récupérer la dernière AMI EKS optimisée pour Kubernetes 1.34
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.34/amazon-linux-2/recommended/image_id \
  --region ${AWS_REGION} \
  --query 'Parameter.Value' \
  --output text)

echo "AMI ID optimisée EKS: ${AMI_ID}"
```

### 3.2 — Mettre à jour le fichier karpenter-nodepool.yaml

Ouvre le fichier `infra/karpenter-nodepool.yaml` et remplace l'AMI ID :

```bash
sed -i "s/ami-xxxxxxxxx/${AMI_ID}/g" infra/karpenter-nodepool.yaml
```

Vérifie le fichier :

```bash
cat infra/karpenter-nodepool.yaml
```

### 3.3 — Déployer le NodePool et EC2NodeClass

```bash
kubectl apply -f infra/karpenter-nodepool.yaml
```

### 3.4 — Vérifier le déploiement du NodePool

```bash
# Vérifier que le NodePool est créé
kubectl get nodepool

# Tu devrais voir
# NAME      NODECLASS   NODES   READY   AGE
# default   default     0       True    10s
```

Vérifier l'EC2NodeClass :

```bash
kubectl get ec2nodeclass

# Tu devrais voir
# NAME      READY   AGE
# default   True    10s
```

Vérifier le statut détaillé :

```bash
# Vérifier que l'AMI est prête
kubectl get ec2nodeclass default -o jsonpath='{.status.conditions[?(@.type=="AMIsReady")]}' | jq

# Voir les détails du NodePool
kubectl describe nodepool default

# Voir les détails de l'EC2NodeClass
kubectl describe ec2nodeclass default
```

Si tout est OK, tu devrais voir `Ready: True` pour le NodePool et l'EC2NodeClass.

---

## ✅ Récapitulatif

Tu as maintenant :
- ✅ Un cluster EKS avec 2 nodes système
- ✅ Karpenter installé et configuré avec des **permissions IAM sécurisées**
- ✅ Un NodePool Karpenter prêt à créer des nodes à la demande
- ✅ Configuration testée et vérifiée

**Prochaine étape** : Tester le scaling avec une application de test ! 🚀

Consulte le fichier principal [README.md](README.md) pour déployer une application et voir Karpenter en action.

---

## 🔧 Troubleshooting

### Erreur : `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Symptôme** : Les pods Karpenter sont en `CrashLoopBackOff` et les logs montrent :
```
api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Cause** : Le service account Karpenter a été créé dans le namespace `kube-system` mais Karpenter tourne dans le namespace `karpenter`. Le trust policy du rôle IAM ne correspond pas au namespace réel.

**Solution** : Mettre à jour le trust policy du rôle IAM via la Console AWS pour changer :
- De : `"system:serviceaccount:kube-system:karpenter"`
- À : `"system:serviceaccount:karpenter:karpenter"`

**Prévention** : Créer directement le service account dans le namespace `karpenter` (comme indiqué dans l'étape 1.3 ci-dessus).

### Erreur : `AccessDenied: Not authorized to perform iam:ListInstanceProfiles`

**Symptôme** : Les logs Karpenter montrent des erreurs répétées :
```
api error AccessDenied: User: ... is not authorized to perform: iam:ListInstanceProfiles
```

**Cause** : La policy IAM `KarpenterControllerPolicy` ne contient pas les permissions IAM nécessaires.

**Solution** : Ajouter ces permissions à la policy via la Console AWS (section IAM) :
```json
{
  "Sid": "AllowIAMInstanceProfileActions",
  "Effect": "Allow",
  "Action": [
    "iam:ListInstanceProfiles",
    "iam:GetInstanceProfile"
  ],
  "Resource": "*"
}
```

Puis redémarrer les pods Karpenter :
```bash
kubectl rollout restart deployment karpenter -n karpenter
```
