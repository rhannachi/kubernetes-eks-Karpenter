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
TAGGED_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].SubnetId' \
  --output text)

if [ -n "$TAGGED_SUBNETS" ]; then
  echo "   ✅ Sous-réseaux taggés trouvés:"
  echo "   $TAGGED_SUBNETS"
else
  echo "   ❌ AUCUN sous-réseau taggé avec karpenter.sh/discovery=${CLUSTER_NAME}"
  exit 1
fi
echo ""

# 6️⃣ Vérifier les tags du security group
echo "6️⃣  Vérification des tags sur le security group..."
TAGGED_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'SecurityGroups[*].GroupId' \
  --output text)

if [ -n "$TAGGED_SG" ]; then
  echo "   ✅ Security group taggé trouvé: $TAGGED_SG"
else
  echo "   ❌ AUCUN security group taggé avec karpenter.sh/discovery=${CLUSTER_NAME}"
  exit 1
fi
echo ""

echo "======================================"
echo "✅ ÉTAPE 1 VALIDÉE !"
echo "======================================"
echo ""
echo "Vous pouvez passer à l'ÉTAPE 2 !"
