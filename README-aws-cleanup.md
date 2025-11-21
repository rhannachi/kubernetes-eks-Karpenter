# TODO (tester) Nettoyage complet et suppression du cluster EKS avec Karpenter

Ce document détaille le processus **complet et sûr** pour supprimer toute la configuration AWS mise en place pour un cluster EKS avec Karpenter. Le nettoyage suit l'ordre **inverse** des étapes d'installation pour éviter les dépendances orphelines.

---

## ⚠️ AVERTISSEMENT CRITIQUE

> **Avant de commencer** : Cette opération **SUPPRIMERA définitivement** :
> - ❌ Le cluster EKS entier
> - ❌ Tous les nodes EC2 (système + Karpenter)
> - ❌ Tous les pods et données en mémoire
> - ❌ Les rôles IAM et policies
> - ❌ Les ressources réseau associées
>
> **⚠️ CETTE OPÉRATION EST IRRÉVERSIBLE**
>
> Les données persistantes (EBS, RDS, S3, etc.) ne seront pas supprimées automatiquement, mais les attachements à EC2 seront détruits.

---

## 📋 Prérequis Avant Nettoyage

Assurez-vous d'avoir :
- ✅ AWS CLI configuré
- ✅ kubectl installé
- ✅ eksctl installé
- ✅ Accès au cluster EKS actuel
- ✅ Les variables d'environnement définies

```bash
# Variables de configuration (DOIVENT être identiques à celles de l'installation)
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Vérification
echo "Configuration du nettoyage :"
echo "  Nom du Cluster   : ${CLUSTER_NAME}"
echo "  Région AWS       : ${AWS_REGION}"
echo "  ID du Compte     : ${AWS_ACCOUNT_ID}"
```

---

## 🧹 Étape 1 : Suppression de l'Application de Démonstration

**Ordre de suppression** :
1. Load-generator
2. Pods php-apache et HPA
3. PVC et volumes associés

### 1.1 — Supprimer le load-generator

```bash
# Vérifier que le load-generator existe
kubectl get pods -A | grep load-generator

# Supprimer le load-generator (s'il existe)
kubectl delete -f k8s/utils/load-generator.yaml --ignore-not-found

# OU supprimer directement par nom
kubectl delete pod load-generator --ignore-not-found
```

### 1.2 — Supprimer l'application php-apache et le HPA

```bash
# Supprimer TOUS les éléments déployés via kustomize
kubectl delete -k ./k8s/base

# Vérifier que tout est supprimé
kubectl get deployment
kubectl get hpa
kubectl get pvc
```

### 1.3 — Attendre que les pods se terminent

```bash
# Vérifier que les pods de l'application sont terminés
watch kubectl get pods --all-namespaces

# Appuyer sur Ctrl+C quand tous les pods d'application sont partis
# Les pods système (karpenter, metrics-server, coredns) doivent rester
```

### 1.4 — Vérification

Les seuls pods restants doivent être dans les namespaces :
- `karpenter`
- `kube-system`
- `kube-node-lease`
- `default` (vide)

---

## 🧹 Étape 2 : Suppression des Ressources Karpenter (NodePool et EC2NodeClass)

### 2.1 — Supprimer le NodePool

Le NodePool contrôle le provisionnement des nodes Karpenter.

```bash
# Vérifier la présence du NodePool
kubectl get nodepool

# Supprimer le NodePool
kubectl delete nodepool microservices-general-ondemand

# Attendre que Karpenter consolide et supprime les nodes
# (Cela peut prendre 2-3 minutes)
watch kubectl get nodes
```

### 2.2 — Supprimer l'EC2NodeClass

L'EC2NodeClass définit la configuration des instances EC2.

```bash
# Vérifier la présence de l'EC2NodeClass
kubectl get ec2nodeclass

# Supprimer l'EC2NodeClass
kubectl delete ec2nodeclass microservices-general-al2

# Vérifier la suppression
kubectl get ec2nodeclass
```

### 2.3 — Attendre la consolidation Karpenter

```bash
# Observer les nodes disparaître progressivement
watch -n 3 kubectl get nodes

# Attendre jusqu'à ce que seuls les 2 nodes système restent
# Signature des nodes système : label role=system et taint CriticalAddonsOnly
kubectl get nodes -L role
```

**Vous devriez voir à la fin** :
- 2 nodes système (t3.medium) avec label `role=system`
- 0 nodes Karpenter

---

## 🧹 Étape 3 : Désinstallation de Karpenter (Helm)

### 3.1 — Vérifier l'installation Helm

```bash
# Lister les releases Helm
helm list -n karpenter

# Vérifier les pods Karpenter
kubectl get pods -n karpenter
```

### 3.2 — Désinstaller Karpenter via Helm

```bash
# Désinstaller la release Helm
helm uninstall karpenter -n karpenter

# Attendre que les pods Karpenter se terminent
watch kubectl get pods -n karpenter
```

### 3.3 — Supprimer les CRDs Karpenter (si nécessaire)

> ⚠️ **IMPORTANT** : Helm peut ne pas supprimer les CRDs automatiquement

```bash
# Vérifier les CRDs Karpenter
kubectl get crd | grep karpenter

# Supprimer les CRDs (cela va aussi supprimer tous les objets associés)
kubectl delete crd nodepools.karpenter.sh
kubectl delete crd nodeclaims.karpenter.sh
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws

# Vérifier la suppression
kubectl get crd | grep karpenter
```

### 3.4 — Supprimer le namespace Karpenter

```bash
# Supprimer le namespace entier
kubectl delete namespace karpenter

# Vérifier la suppression
kubectl get namespaces | grep karpenter
```

---

## 🧹 Étape 4 : Suppression des Ressources IAM Karpenter

### 4.1 — Supprimer le Service Account IAM (IRSA)

L'IRSA (IAM Role for Service Account) a été créé par eksctl et doit être supprimé avec le même outil.

```bash
# Supprimer le service account IAM
eksctl delete iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --name=karpenter \
  --namespace=karpenter

# Attendre que la suppression se complète (peut prendre 30 secondes)
sleep 30

# Vérifier la suppression de la policy attachée
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME} \
  2>/dev/null | grep -q PolicyVersionList || echo "Policy supprimée"
```

### 4.2 — Supprimer la Policy IAM Karpenter Controller

> ⚠️ **NOTE** : Cette policy peut avoir été créée via la console AWS. Elle doit être supprimée explicitement.

```bash
# Détacher la policy du service account (si encore attachée)
aws iam detach-role-policy \
  --role-name karpenter-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME} \
  2>/dev/null || true

# Vérifier si la policy existe
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}"
if aws iam get-policy --policy-arn ${POLICY_ARN} &>/dev/null; then
    echo "Suppression de la policy Karpenter..."

    # Supprimer toutes les versions non-par défaut
    POLICY_VERSIONS=$(aws iam list-policy-versions \
        --policy-arn ${POLICY_ARN} \
        --query 'Versions[?!IsDefaultVersion].VersionId' \
        --output text)

    for VERSION in $POLICY_VERSIONS; do
        aws iam delete-policy-version \
            --policy-arn ${POLICY_ARN} \
            --version-id ${VERSION}
    done

    # Supprimer la policy
    aws iam delete-policy --policy-arn ${POLICY_ARN}
    echo "✅ Policy Karpenter supprimée"
else
    echo "⚠️ Policy non trouvée (peut avoir été supprimée)"
fi
```

### 4.3 — Supprimer le Rôle IAM des Nodes Karpenter

Le rôle `KarpenterNodeRole-${CLUSTER_NAME}` est utilisé par les instances EC2 créées par Karpenter.

```bash
# Vérifier que le rôle existe
aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME} &>/dev/null && echo "Rôle trouvé" || echo "Rôle non trouvé"

# Détacher toutes les policies du rôle
ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"

aws iam list-attached-role-policies --role-name ${ROLE_NAME} \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text | tr '\t' '\n' | while read POLICY_ARN; do
    if [[ ! -z "$POLICY_ARN" ]]; then
        echo "Détachement : $POLICY_ARN"
        aws iam detach-role-policy \
          --role-name ${ROLE_NAME} \
          --policy-arn ${POLICY_ARN}
    fi
done

# Supprimer l'instance profile
INSTANCE_PROFILE_NAME="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"

if aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} &>/dev/null; then
    # Retirer le rôle de l'instance profile
    aws iam remove-role-from-instance-profile \
      --instance-profile-name ${INSTANCE_PROFILE_NAME} \
      --role-name ${ROLE_NAME}

    # Supprimer l'instance profile
    aws iam delete-instance-profile \
      --instance-profile-name ${INSTANCE_PROFILE_NAME}

    echo "✅ Instance profile supprimé"
fi

# Supprimer le rôle
aws iam delete-role --role-name ${ROLE_NAME}
echo "✅ Rôle IAM des nodes supprimé"
```

### 4.4 — Vérification

```bash
# Vérifier que toutes les ressources IAM Karpenter sont supprimées
echo "Vérification des ressources IAM Karpenter..."

# Vérifier les policies
aws iam list-policies --scope Local \
  --query "Policies[?contains(PolicyName, 'Karpenter')]" \
  --output table

# Vérifier les rôles
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'Karpenter')]" \
  --output table

# Vérifier les instance profiles
aws iam list-instance-profiles \
  --query "InstanceProfiles[?contains(InstanceProfileName, 'Karpenter')]" \
  --output table
```

---

## 🧹 Étape 5 : Suppression des Tags AWS (Découverte Karpenter)

Les tags `karpenter.sh/discovery` ont été appliqués aux sous-réseaux et security groups pour permettre à Karpenter de les découvrir automatiquement. Ces tags doivent être supprimés.

### 5.1 — Récupérer et supprimer les tags des sous-réseaux

```bash
# Récupérer les subnets avec le tag karpenter.sh/discovery
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].SubnetId' \
  --output text)

if [[ ! -z "$SUBNETS" ]]; then
    echo "Suppression des tags des sous-réseaux..."
    for SUBNET in $SUBNETS; do
        aws ec2 delete-tags \
          --resources $SUBNET \
          --tags Key=karpenter.sh/discovery Key=eks:cluster-name
        echo "✅ Tags supprimés du subnet : $SUBNET"
    done
else
    echo "⚠️ Aucun subnet avec le tag karpenter.sh/discovery trouvé"
fi
```

### 5.2 — Suppression des tags du Security Group

```bash
# Récupérer le security group du cluster
CLUSTER_SG=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

if [[ ! -z "$CLUSTER_SG" && "$CLUSTER_SG" != "None" ]]; then
    echo "Suppression des tags du security group : $CLUSTER_SG"
    aws ec2 delete-tags \
      --resources $CLUSTER_SG \
      --tags Key=karpenter.sh/discovery Key=eks:cluster-name
    echo "✅ Tags supprimés du security group"
else
    echo "⚠️ Security group du cluster non trouvé"
fi
```

### 5.3 — Vérification

```bash
# Vérifier qu'aucun subnet n'a le tag karpenter.sh/discovery
REMAINING=$(aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].SubnetId' \
  --output text)

if [[ -z "$REMAINING" ]]; then
    echo "✅ Tous les tags Karpenter ont été supprimés"
else
    echo "❌ Des tags Karpenter restent : $REMAINING"
fi
```

---

## 🧹 Étape 6 : Suppression du Cluster EKS

> ⚠️ **ATTENTION** : Cette étape va supprimer le cluster entier et tous les nodes système.

### 6.1 — Vérifier que le cluster existe

```bash
# Vérifier l'existence du cluster
aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --output table
```

### 6.2 — Supprimer tous les LoadBalancers ou Ingresses

Les LoadBalancers AWS provisionnés par Kubernetes doivent être supprimés avant le cluster.

```bash
# Supprimer tous les services de type LoadBalancer
kubectl get service -A -o wide | grep LoadBalancer

# Si des services existent, les supprimer
kubectl delete service <service-name> -n <namespace> --ignore-not-found
```

### 6.3 — Supprimer les volumes persistants en attente

```bash
# Lister les PVC et PV
kubectl get pvc -A
kubectl get pv

# Supprimer les PVC restantes
kubectl delete pvc -A --all
```

### 6.4 — Supprimer le cluster EKS avec eksctl

```bash
# Suppression du cluster
# ⚠️ CETTE OPÉRATION EST IRRÉVERSIBLE
echo "⚠️ Suppression du cluster ${CLUSTER_NAME} en cours..."
eksctl delete cluster \
  --name=${CLUSTER_NAME} \
  --region=${AWS_REGION}

# Attendre la suppression (peut prendre 15-20 minutes)
# Vous pouvez vérifier la progression dans la console AWS
```

### 6.5 — Vérifier la suppression du cluster

```bash
# Vérifier que le cluster n'existe plus
aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  2>&1 | grep -q "ResourceNotFoundException" && \
  echo "✅ Cluster complètement supprimé" || \
  echo "❌ Cluster still exists"
```

---

## 🧹 Étape 7 : Nettoyage de la Configuration AWS Restante

### 7.1 — Vérifier les ressources EC2 orphelines

```bash
# Lister tous les instances EC2 du cluster (devrait être vide après eksctl delete)
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --region ${AWS_REGION} \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

### 7.2 — Vérifier les VPC et ressources réseau

Les VPC, subnets, et security groups créés par eksctl devraient être supprimés automatiquement.

```bash
# Lister les VPC associées au cluster
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:eksctl.io/v1alpha5/cluster-name,Values=${CLUSTER_NAME}" \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [[ ! -z "$VPC_ID" && "$VPC_ID" != "None" ]]; then
    echo "⚠️ VPC orpheline trouvée : $VPC_ID"
    echo "Elle sera supprimée manuellement si nécessaire"
fi
```

### 7.3 — Vérifier les Elastic IPs

```bash
# Lister les Elastic IPs non associées (créées par le cluster)
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null]' \
  --output table
```

---

## 🧹 Étape 8 : Nettoyage de la Configuration Utilisateur IAM (Optionnel)

> ⚠️ **OPTIONNEL** : Supprimer l'utilisateur IAM `eks-user` si vous n'en avez plus besoin. Sinon, laissez-le pour des deployments futurs.

### 8.1 — Révoquer les Access Keys

```bash
# Lister les access keys de l'utilisateur eks-user
aws iam list-access-keys --user-name eks-user

# Supprimer chaque access key (remplacer AKIAXXXXXXXX par l'ID réel)
aws iam delete-access-key --user-name eks-user --access-key-id AKIAXXXXXXXX
```

### 8.2 — Détacher les policies du groupe

```bash
# Détacher les policies du groupe eks-user-group
aws iam list-attached-group-policies --group-name eks-user-group \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text | tr '\t' '\n' | while read POLICY_ARN; do
    if [[ ! -z "$POLICY_ARN" ]]; then
        echo "Détachement : $POLICY_ARN"
        aws iam detach-group-policy \
          --group-name eks-user-group \
          --policy-arn ${POLICY_ARN}
    fi
done
```

### 8.3 — Supprimer l'utilisateur du groupe

```bash
# Supprimer l'utilisateur du groupe
aws iam remove-user-from-group \
  --group-name eks-user-group \
  --user-name eks-user
```

### 8.4 — Supprimer la policy EKS personnalisée

```bash
# Supprimer la policy EKSAdminPolicy
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/EKSAdminPolicy"

# Vérifier si la policy existe
if aws iam get-policy --policy-arn ${POLICY_ARN} &>/dev/null; then
    # Supprimer les versions non-par défaut
    POLICY_VERSIONS=$(aws iam list-policy-versions \
        --policy-arn ${POLICY_ARN} \
        --query 'Versions[?!IsDefaultVersion].VersionId' \
        --output text)

    for VERSION in $POLICY_VERSIONS; do
        aws iam delete-policy-version \
            --policy-arn ${POLICY_ARN} \
            --version-id ${VERSION}
    done

    # Supprimer la policy
    aws iam delete-policy --policy-arn ${POLICY_ARN}
    echo "✅ Policy EKSAdminPolicy supprimée"
fi
```

### 8.5 — Supprimer le groupe IAM

```bash
# Supprimer le groupe eks-user-group
aws iam delete-group --group-name eks-user-group

echo "✅ Groupe IAM supprimé"
```

### 8.6 — Supprimer l'utilisateur IAM (⚠️ DÉFINITIF)

```bash
# ⚠️ ATTENTION : Cette opération est irréversible
# Supprimer l'utilisateur eks-user

# Vérifier d'abord s'il a des access keys restantes
aws iam list-access-keys --user-name eks-user

# Si des access keys existent, les supprimer
# aws iam delete-access-key --user-name eks-user --access-key-id AKIAXXXXXXXX

# Supprimer l'utilisateur
aws iam delete-user --user-name eks-user

echo "✅ Utilisateur IAM eks-user supprimé"
```

---

## ✅ Vérification Complète du Nettoyage

Après avoir exécuté toutes les étapes, exécutez ce script de vérification complète :

```bash
#!/bin/bash

echo "========================================"
echo "🔍 Vérification du Nettoyage Complet"
echo "========================================"

CLUSTER_NAME="microservices-demo-cluster"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Vérifier le cluster
echo ""
echo "1️⃣ Vérification du Cluster EKS..."
if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "❌ Cluster existe toujours"
else
    echo "✅ Cluster supprimé"
fi

# 2. Vérifier les policies Karpenter
echo ""
echo "2️⃣ Vérification des Policies IAM Karpenter..."
KARPENTER_POLICIES=$(aws iam list-policies --scope Local \
  --query "Policies[?contains(PolicyName, 'Karpenter')].PolicyName" \
  --output text)
if [[ ! -z "$KARPENTER_POLICIES" ]]; then
    echo "❌ Policies Karpenter trouvées: $KARPENTER_POLICIES"
else
    echo "✅ Policies Karpenter supprimées"
fi

# 3. Vérifier les rôles Karpenter
echo ""
echo "3️⃣ Vérification des Rôles IAM Karpenter..."
KARPENTER_ROLES=$(aws iam list-roles \
  --query "Roles[?contains(RoleName, 'Karpenter')].RoleName" \
  --output text)
if [[ ! -z "$KARPENTER_ROLES" ]]; then
    echo "❌ Rôles Karpenter trouvés: $KARPENTER_ROLES"
else
    echo "✅ Rôles Karpenter supprimés"
fi

# 4. Vérifier les instance profiles
echo ""
echo "4️⃣ Vérification des Instance Profiles..."
INSTANCE_PROFILES=$(aws iam list-instance-profiles \
  --query "InstanceProfiles[?contains(InstanceProfileName, 'Karpenter')].InstanceProfileName" \
  --output text)
if [[ ! -z "$INSTANCE_PROFILES" ]]; then
    echo "❌ Instance profiles trouvés: $INSTANCE_PROFILES"
else
    echo "✅ Instance profiles supprimés"
fi

# 5. Vérifier les instances EC2
echo ""
echo "5️⃣ Vérification des Instances EC2..."
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --region ${AWS_REGION} \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)
if [[ ! -z "$INSTANCES" ]]; then
    echo "❌ Instances EC2 trouvées: $INSTANCES"
else
    echo "✅ Instances EC2 supprimées"
fi

# 6. Vérifier les tags Karpenter
echo ""
echo "6️⃣ Vérification des Tags Karpenter..."
TAGGED_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
  --query 'Subnets[*].SubnetId' \
  --output text)
if [[ ! -z "$TAGGED_SUBNETS" ]]; then
    echo "❌ Subnets avec tags Karpenter trouvés: $TAGGED_SUBNETS"
else
    echo "✅ Tags Karpenter supprimés"
fi

# 7. Vérifier kubeconfig
echo ""
echo "7️⃣ Vérification de kubeconfig..."
if kubectl config current-context | grep -q ${CLUSTER_NAME}; then
    echo "⚠️ Contexte $CLUSTER_NAME toujours dans kubeconfig"
    echo "   Recommandé de supprimer manuellement ou le laisser (inoffensif)"
else
    echo "✅ Contexte supprimé de kubeconfig"
fi

echo ""
echo "========================================"
echo "✅ Nettoyage Complété!"
echo "========================================"
```

**Pour exécuter ce script** :

```bash
# Sauvegarder le script
cat > verify-cleanup.sh << 'EOF'
[Coller le contenu du script ci-dessus]
EOF

# Rendre exécutable et lancer
chmod +x verify-cleanup.sh
./verify-cleanup.sh
```

---

## 🔧 Nettoyage Manuel de kubeconfig (Optionnel)

Si vous n'avez plus besoin du contexte Kubernetes, vous pouvez le supprimer manuellement :

```bash
# Lister les contextes
kubectl config get-contexts

# Supprimer le contexte du cluster
kubectl config delete-context <context-name>

# Supprimer la configuration utilisateur
kubectl config delete-user <user-name>

# Supprimer le cluster de kubeconfig
kubectl config delete-cluster <cluster-arn>
```

---

## 📝 Résumé du Nettoyage Complet

### Ordre de Suppression (du haut vers le bas) :

| Étape | Ressource | État |
|-------|-----------|------|
| 1 | Application php-apache + Load-generator | ❌ Supprimé |
| 2 | NodePool + EC2NodeClass Karpenter | ❌ Supprimé |
| 3 | Karpenter Helm Release + CRDs + Namespace | ❌ Supprimé |
| 4 | Service Account IAM + Rôles IAM | ❌ Supprimé |
| 5 | Tags Karpenter (subnets + SG) | ❌ Supprimé |
| 6 | Cluster EKS + Nodes Système | ❌ Supprimé |
| 7 | Ressources Réseau Orphelines | ✅ Vérifiées |
| 8 | Utilisateur IAM eks-user (optionnel) | ⚠️ Optionnel |

---

## 🆘 Dépannage

### Problème : Cluster ne se supprime pas

```bash
# Vérifier les LoadBalancers restants
aws elb describe-load-balancers --region ${AWS_REGION}
aws elbv2 describe-load-balancers --region ${AWS_REGION}

# Supprimer manuellement si nécessaire
aws elbv2 delete-load-balancer --load-balancer-arn <arn>
```

### Problème : VPC ne se supprime pas

```bash
# Lister les VPC
aws ec2 describe-vpcs --region ${AWS_REGION}

# Vérifier les dépendances (ENI, Security Groups, etc.)
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --region ${AWS_REGION}
```

### Problème : Rôle IAM verrouillé

```bash
# Vérifier les entités attachées
aws iam get-role --role-name <role-name>

# Vérifier l'historique d'utilisation (CloudTrail)
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=<role-name>
```

---

## ✅ Confirmation du Succès

Si vous voyez ces messages, le nettoyage est réussi ✅ :

```
✅ Cluster supprimé
✅ Policies Karpenter supprimées
✅ Rôles Karpenter supprimés
✅ Instance profiles supprimés
✅ Instances EC2 supprimées
✅ Tags Karpenter supprimés
✅ Nettoyage Complété!
```

---

## 📌 Prochaines Étapes

Après ce nettoyage complet, vous pouvez :

1. **Redéployer** un nouveau cluster EKS en suivant les étapes du `README.md`
2. **Supprimer le repository local** si vous n'en avez plus besoin
3. **Configurer CloudTrail** pour auditer les futurs changements AWS
4. **Documenter** les leçons apprises de ce déploiement

---

**Créé pour la documentation EKS Karpenter**
*Mise à jour : 2025-11-21*
