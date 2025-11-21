# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a tutorial project demonstrating Kubernetes autoscaling on AWS EKS using **Karpenter** (v1.8.2). The project is in French and provides step-by-step instructions for setting up an EKS cluster with Karpenter-managed node autoscaling and HPA (Horizontal Pod Autoscaler).

**Architecture Pattern:**
- **Static System Nodes**: 2 t3.medium nodes (managed by EKS) running Karpenter controller, metrics-server, and core services
- **Dynamic Application Nodes**: On-demand t3.medium/t3.large nodes (managed by Karpenter) for application workloads
- **Separation via Taints**: System nodes have `CriticalAddonsOnly=true:NoSchedule` taint to prevent application pods from scheduling on them

## Key Configuration Variables

These environment variables are used throughout the setup scripts and must be consistent:

```bash
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Essential Commands

### Cluster Management

```bash
# Create EKS cluster (15-20 minutes)
eksctl create cluster -f ./infra/cluster.yaml

# Delete cluster
eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Check cluster status
kubectl get nodes
kubectl top nodes  # Requires metrics-server
```

### Karpenter Installation & Management

```bash
# Install Karpenter via Helm
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.8.2 \
  --namespace karpenter \
  --set "serviceAccount.name=karpenter" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --wait

# Deploy NodePool and EC2NodeClass
kubectl apply -f infra/karpenter-nodepool.yaml

# Check Karpenter status
kubectl get pods -n karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50
kubectl get nodepool
kubectl get ec2nodeclass
```

### Application Deployment & Testing

```bash
# Deploy php-apache demo app with HPA
kubectl apply -k ./k8s/base

# Check deployment
kubectl get deployment php-apache
kubectl get hpa php-apache-hpa
kubectl get pods

# Generate load to test autoscaling
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Inside the shell:
while true; do wget -q -O- http://php-apache; done

# Monitor autoscaling in another terminal
watch kubectl get pods
watch kubectl get nodes
watch kubectl get hpa
```

### Verification Scripts

```bash
# Verify Step 1: IAM roles, service accounts, subnet/SG tags
./scripts/verify-step1.sh

# Verify Step 2: Karpenter installation
./scripts/verify-step2.sh

# Verify Step 3: NodePool and EC2NodeClass configuration
./scripts/verify-step3.sh
```

## Architecture & Infrastructure

### IAM Configuration

**Two Separate IAM Roles:**

1. **Karpenter Controller Role** (IRSA - IAM Role for Service Account):
   - Created via: `eksctl create iamserviceaccount`
   - Policy: `KarpenterControllerPolicy-${CLUSTER_NAME}` (see `infra/karpenter-controller-policy.json`)
   - Used by: Karpenter controller pods to provision/terminate EC2 instances
   - Attached to: ServiceAccount `karpenter` in namespace `karpenter`

2. **Karpenter Node Role** (EC2 Instance Profile):
   - Name: `KarpenterNodeRole-${CLUSTER_NAME}`
   - Trust policy: `infra/karpenter-node-trust-policy.json`
   - Policies: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly, AmazonSSMManagedInstanceCore
   - Used by: EC2 instances launched by Karpenter to join the cluster

**User IAM Configuration:**
- Group: `eks-user-group`
- Custom policy: `EKSAdminPolicy` (see `infra/eks-admin-policy.json`)
- Follows least-privilege principle for EKS/Karpenter operations

### Resource Discovery Pattern

Karpenter discovers AWS resources (subnets, security groups) via tags:

```bash
# Tag format
karpenter.sh/discovery: ${CLUSTER_NAME}
```

This is applied to:
- All cluster subnets
- Cluster security group

### Karpenter Configuration

**NodePool** (`infra/karpenter-nodepool.yaml`):
- Name: `microservices-general-ondemand`
- Capacity type: on-demand only
- Instance types: t3.medium, t3.large
- CPU limit: 100 cores
- Consolidation: Enabled (1 minute after empty/underutilized)

**EC2NodeClass**:
- AMI Family: AL2 (Amazon Linux 2)
- AMI ID must be updated before deployment (see step 3.1 in README-aws-karpenter.md)
- Role: References `KarpenterNodeRole-${CLUSTER_NAME}`
- Subnet/SG discovery: Via `karpenter.sh/discovery` tags

### Demo Application

**php-apache Deployment** (`k8s/base/deployment.yaml`):
- Image: `k8s.gcr.io/hpa-example`
- Resources:
  - CPU request: 200m (base for HPA calculation)
  - CPU limit: 500m
- Tolerations: Can run on system nodes (for demo purposes)

**HPA Configuration** (`k8s/base/hpa.yaml`):
- Min replicas: 1
- Max replicas: 10
- Target: 50% CPU utilization (of the 200m request)

**Expected Behavior:**
1. Load increases → HPA scales pods to max 10 replicas
2. System nodes fill up → Karpenter provisions new nodes
3. Load decreases → HPA scales down pods
4. Nodes underutilized → Karpenter consolidates/removes nodes after 1 minute

## Important File Patterns

- `infra/*.yaml`: EKS cluster and Karpenter resource definitions
- `infra/*.json`: IAM policy documents (require variable substitution with `sed`)
- `k8s/base/*.yaml`: Demo application manifests
- `scripts/verify-step*.sh`: Validation scripts for each setup phase
- `README-aws-*.md`: Step-by-step French tutorial documentation

## Common Workflows

### Updating AMI for Karpenter Nodes

```bash
# Get latest EKS-optimized AMI (Kubernetes 1.34)
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.34/amazon-linux-2/recommended/image_id \
  --region ${AWS_REGION} \
  --query 'Parameter.Value' \
  --output text)

# Update NodePool configuration
sed -i "s/ami-xxxxxxxxx/${AMI_ID}/g" infra/karpenter-nodepool.yaml

# Apply changes
kubectl apply -f infra/karpenter-nodepool.yaml
```

### Updating IAM Policy Variables

All IAM policy JSON files contain placeholder variables that must be substituted:

```bash
# For eks-admin-policy.json
sed -i "s/\${AWS_REGION}/${AWS_REGION}/g" infra/eks-admin-policy.json

# For karpenter-controller-policy.json
sed -i "s/\${AWS_REGION}/${AWS_REGION}/g" infra/karpenter-controller-policy.json
sed -i "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" infra/karpenter-controller-policy.json
sed -i "s/\${CLUSTER_NAME}/${CLUSTER_NAME}/g" infra/karpenter-controller-policy.json
```

### Troubleshooting Karpenter Issues

```bash
# Check Karpenter controller logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Common issues to look for:
# - AccessDenied errors → Check IAM roles and policies
# - AMI not found → Update AMI ID in karpenter-nodepool.yaml
# - Subnet/SG not found → Verify karpenter.sh/discovery tags
# - Node join failures → Check KarpenterNodeRole policies

# Verify ServiceAccount IAM role annotation
kubectl get sa karpenter -n karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Check NodePool status
kubectl describe nodepool microservices-general-ondemand

# Check EC2NodeClass status
kubectl describe ec2nodeclass microservices-general-al2
```

### Debugging HPA Issues

```bash
# Check HPA status and events
kubectl describe hpa php-apache-hpa

# Verify metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top pods

# Common issues:
# - "unable to get metrics" → metrics-server not ready (wait 2-3 minutes)
# - HPA shows <unknown> → Check pod resource requests are defined
# - Pods not scaling → Verify CPU utilization exceeds 50% threshold
```

## Security Considerations

- **Never use AdministratorAccess** for the IAM user
- IAM policies follow least-privilege principle
- System nodes are tainted to prevent application workload interference
- OIDC provider enabled for IRSA (secure pod-level IAM authentication)
- All policy creation requires admin access via AWS Console (documented workflow)

## Testing Scenarios

The project is designed to demonstrate:
1. **HPA scaling**: Pods scale from 1 to 10 replicas under load
2. **Karpenter node provisioning**: New nodes automatically added when pods are pending
3. **Node consolidation**: Nodes removed when underutilized (after 1 minute)
4. **Cost optimization**: On-demand instances, efficient resource packing
