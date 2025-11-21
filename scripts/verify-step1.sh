#!/bin/bash

export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "======================================"
echo "🔍 VÉRIFICATION DE L'ÉTAPE 1"
echo "======================================"
echo ""

# 1️⃣ Vérifier le Service Account Karpenter
echo "1️⃣  Vérification du Service Account IAM..."
kubectl get sa karpenter -n karpenter &>/dev/null
if [ $? -eq 0 ]; then
  echo "   ✅ Service Account 'karpenter' existe dans karpenter"
  kubectl describe sa karpenter -n karpenter | grep "eks.amazonaws.com/role-arn"
else
  echo "   ❌ Service Account 'karpenter' n'existe PAS"
  exit 1
fi
echo ""

# 2️⃣ Vérifier le rôle IAM des nodes
echo "2️⃣  Vérification du rôle KarpenterNodeRole..."
aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME} &>/dev/null
if [ $? -eq 0 ]; then
  echo "   ✅ Rôle KarpenterNodeRole-${CLUSTER_NAME} existe"
else
  echo "   ❌ Rôle KarpenterNodeRole-${CLUSTER_NAME} n'existe PAS"
  exit 1
fi
echo ""

# 3️⃣ Vérifier les policies attachées
echo "3️⃣  Vérification des policies attachées au rôle node..."
POLICIES=$(aws iam list-attached-role-policies --role-name KarpenterNodeRole-${CLUSTER_NAME} --query 'AttachedPolicies[*].PolicyName' --output text)
echo "   Policies attachées: $POLICIES"

if [[ $POLICIES == *"AmazonEKSWorkerNodePolicy"* ]]; then
  echo "   ✅ AmazonEKSWorkerNodePolicy"
else
  echo "   ❌ AmazonEKSWorkerNodePolicy MANQUANTE"
fi

if [[ $POLICIES == *"AmazonEKS_CNI_Policy"* ]]; then
  echo "   ✅ AmazonEKS_CNI_Policy"
else
  echo "   ❌ AmazonEKS_CNI_Policy MANQUANTE"
fi

if [[ $POLICIES == *"AmazonEC2ContainerRegistryReadOnly"* ]]; then
  echo "   ✅ AmazonEC2ContainerRegistryReadOnly"
else
  echo "   ❌ AmazonEC2ContainerRegistryReadOnly MANQUANTE"
fi

if [[ $POLICIES == *"AmazonSSMManagedInstanceCore"* ]]; then
  echo "   ✅ AmazonSSMManagedInstanceCore"
else
  echo "   ❌ AmazonSSMManagedInstanceCore MANQUANTE"
fi
echo ""

# 4️⃣ Vérifier l'instance profile
echo "4️⃣  Vérification de l'instance profile..."
aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} &>/dev/null
if [ $? -eq 0 ]; then
  echo "   ✅ Instance profile KarpenterNodeInstanceProfile-${CLUSTER_NAME} existe"
else
  echo "   ❌ Instance profile n'existe PAS"
  exit 1
fi
echo ""

# 5️⃣ Vérifier les tags des sous-réseaux
echo "5️⃣  Vérification des tags sur les sous-réseaux..."
# Récupérer les sous-réseaux du cluster via l'API EKS
CLUSTER_SUBNETS=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query 'cluster.resourcesVpcConfig.subnetIds' \
  --output text)

# Vérifier les tags des sous-réseaux
TAGGED_SUBNETS=$(aws ec2 describe-subnets \
  --filters \
    "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
    "Name=tag:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].SubnetId' \
  --output text)

TOTAL_CLUSTER_SUBNETS=$(echo "$CLUSTER_SUBNETS" | tr ' ' '\n' | grep -v '^$' | wc -l)
TOTAL_TAGGED_SUBNETS=$(echo "$TAGGED_SUBNETS" | tr ' ' '\n' | grep -v '^$' | wc -l)

if [ "$TOTAL_CLUSTER_SUBNETS" -eq "$TOTAL_TAGGED_SUBNETS" ]; then
  echo "   ✅ Tous les $TOTAL_CLUSTER_SUBNETS sous-réseaux sont taggués correctement"
  echo "   Sous-réseaux taggués : $TAGGED_SUBNETS"

  # Afficher les détails des tags pour chaque sous-réseau
  echo "   Détails des tags :"
  for subnet in $TAGGED_SUBNETS; do
    echo "   Subnet $subnet :"
    aws ec2 describe-subnets \
      --subnet-ids $subnet \
      --query 'Subnets[*].{ID:SubnetId, AZ:AvailabilityZone, Tags:Tags}' \
      --output table
  done
else
  echo "   ❌ Seulement $TOTAL_TAGGED_SUBNETS sur $TOTAL_CLUSTER_SUBNETS sous-réseaux sont taggués"
  echo "   Sous-réseaux du cluster : $CLUSTER_SUBNETS"
  echo "   Sous-réseaux taggués : $TAGGED_SUBNETS"
  exit 1
fi
echo ""

# 6️⃣ Vérifier les tags du security group
echo "6️⃣  Vérification des tags sur le security group..."
CLUSTER_SG=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

TAGGED_SG=$(aws ec2 describe-security-groups \
  --filters \
    "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
    "Name=tag:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --query 'SecurityGroups[*].GroupId' \
  --output text)

if [ "$CLUSTER_SG" = "$TAGGED_SG" ]; then
  echo "   ✅ Security group du cluster correctement taggué : $TAGGED_SG"
  echo "   Détails du security group :"
  aws ec2 describe-security-groups \
    --group-ids $TAGGED_SG \
    --query 'SecurityGroups[*].{Name:GroupName, Description:Description, VPC:VpcId}'
else
  echo "   ❌ Le security group du cluster n'est PAS taggué correctement"
  echo "   Security group du cluster : $CLUSTER_SG"
  echo "   Security group taggué : $TAGGED_SG"
  exit 1
fi
echo ""

echo "======================================"
echo "✅ ÉTAPE 1 VALIDÉE !"
echo "======================================"
echo ""
echo "Vous pouvez passer à l'ÉTAPE 2 !"