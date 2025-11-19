# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kubernetes EKS cluster configuration repository focused on **Karpenter** autoscaling. The project demonstrates how to set up an AWS EKS cluster with Karpenter as the autoscaling solution, replacing traditional Cluster Autoscaler.

**Key architecture decisions:**
- 2 static system nodes (t3.medium) with `CriticalAddonsOnly` taints to run Karpenter and critical services
- Karpenter manages dynamic workload nodes (on-demand only: t3.medium, t3.large)
- IRSA (IAM Roles for Service Accounts) for secure AWS permissions
- Tag-based resource discovery using `karpenter.sh/discovery`

## Project Structure

```
.
├── infra/                    # Infrastructure as Code
│   ├── cluster.yaml          # eksctl cluster definition
│   ├── karpenter-nodepool.yaml    # Karpenter NodePool + EC2NodeClass
│   ├── karpenter-node-trust-policy.json
│   └── metric-server.yaml
├── k8s/
│   ├── base/                 # Sample application (php-apache for HPA demo)
│   │   ├── deployment.yaml   # PHP application with resource requests/limits
│   │   ├── hpa.yaml         # HorizontalPodAutoscaler (50% CPU, 1-10 replicas)
│   │   └── kustomization.yaml
│   └── utils/               # Testing and utilities
│       ├── test-karpenter-scaling.yaml    # Load generator for AWS
│       └── test-minikube-scaling.yaml     # Load generator for minikube
├── verify-step1.sh          # Verification script for IAM roles and service accounts
├── karpenter_cluster_monitor.sh  # Real-time cluster monitoring dashboard
└── cleanup-karpenter.sh     # Cleanup script for Karpenter resources
```

## Common Commands

### Cluster Management

```bash
# Create EKS cluster (15-20 min)
eksctl create cluster -f ./infra/cluster.yaml

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name microservices-demo-cluster

# Delete cluster
eksctl delete cluster --name microservices-demo-cluster --region us-east-1
```

### Karpenter Installation

Set environment variables first:
```bash
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Install via Helm:
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
  --wait
```

### Deploy NodePool and EC2NodeClass

```bash
# Update AMI ID in the file first
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.34/amazon-linux-2/recommended/image_id \
  --region ${AWS_REGION} \
  --query 'Parameter.Value' \
  --output text)

sed -i "s/ami-xxxxxxxxx/${AMI_ID}/g" infra/karpenter-nodepool.yaml

# Apply configuration
kubectl apply -f infra/karpenter-nodepool.yaml
```

### Testing & Monitoring

```bash
# Deploy sample application
kubectl apply -k ./k8s/base

# Deploy load generator (AWS)
kubectl apply -f ./k8s/utils/test-karpenter-scaling.yaml

# Monitor Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Real-time cluster monitoring
./karpenter_cluster_monitor.sh

# Watch cluster scaling
watch kubectl get nodes
kubectl get hpa -w
kubectl get pods -w

# Verify Karpenter resources
kubectl get nodepool
kubectl get ec2nodeclass
kubectl get nodeclaim
```

### Metrics Server

```bash
# Deploy metrics-server
kubectl apply -f infra/metric-server.yaml

# Verify metrics are available
kubectl top nodes
kubectl top pods -A
```

## Architecture Details

### IAM Roles and Permissions

The setup requires three IAM components:

1. **Karpenter Controller Role** (IRSA):
   - Policy: `KarpenterControllerPolicy-${CLUSTER_NAME}` (custom policy with least privilege)
   - Service Account: `karpenter` in namespace `karpenter`
   - Permissions: EC2 instance management, SSM parameter read, pricing API, SQS for interruption handling

2. **Karpenter Node Role**:
   - Role: `KarpenterNodeRole-${CLUSTER_NAME}`
   - Instance Profile: `KarpenterNodeInstanceProfile-${CLUSTER_NAME}`
   - Policies: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly, AmazonSSMManagedInstanceCore

3. **EKS User** (for CLI operations):
   - User: `eks-user`
   - Group: `eks-user-group`
   - Custom policy: `EKSAdminPolicy` with permissions for EKS, EC2, IAM, CloudFormation, etc.

### Resource Tagging

All subnets and security groups must be tagged for Karpenter discovery:
```bash
# Tag subnets
aws ec2 create-tags \
  --resources <subnet-id> \
  --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}

# Tag security group
aws ec2 create-tags \
  --resources <sg-id> \
  --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
```

### Karpenter NodePool Configuration

- **Capacity type**: On-demand only (no spot instances)
- **Instance types**: t3.medium, t3.large
- **CPU limit**: 100 cores total
- **Disruption policy**: WhenEmptyOrUnderutilized with 1-minute consolidation delay
- **AMI**: AL2 (Amazon Linux 2) family, ID must be updated in `karpenter-nodepool.yaml`

### System Node Taints

System nodes have the taint `CriticalAddonsOnly=true:NoSchedule` to prevent application workloads from scheduling there. Karpenter pods include a toleration for this taint in the Helm installation.

## Sequential Setup Guide

The repository follows a 3-step setup process:

1. **Step 1** (README-aws-user.md): AWS user setup with IAM permissions
2. **Step 2** (README-aws-cluster.md): EKS cluster creation and metrics-server deployment
3. **Step 3** (README-aws-karpenter.md): Karpenter IAM roles, installation, and NodePool configuration

Use `./verify-step1.sh` to verify IAM setup before proceeding to Karpenter installation.

## Troubleshooting

### Common Issues

**AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity**
- Cause: Service account namespace mismatch in IAM trust policy
- Solution: Ensure service account is created in the `karpenter` namespace and trust policy references `system:serviceaccount:karpenter:karpenter`

**AccessDenied: iam:ListInstanceProfiles**
- Cause: Missing IAM permissions in KarpenterControllerPolicy
- Solution: Add `iam:ListInstanceProfiles` and `iam:GetInstanceProfile` permissions

**AMI not found**
- Cause: AMI ID placeholder not replaced in karpenter-nodepool.yaml
- Solution: Run the sed command to replace `ami-xxxxxxxxx` with actual AMI ID from SSM parameter

### Verification Commands

```bash
# Check Karpenter pod status
kubectl get pods -n karpenter

# Check CRDs
kubectl get crd | grep karpenter

# Check NodePool/EC2NodeClass status
kubectl describe nodepool default
kubectl describe ec2nodeclass default

# View recent events
kubectl get events -n karpenter --sort-by=.lastTimestamp
```

## Important Notes

- Never use `AdministratorAccess` for Karpenter - always use the custom least-privilege policy
- Karpenter requires OIDC to be enabled on the EKS cluster for IRSA
- The metrics-server is essential for HPA and must be deployed before testing autoscaling
- AMI IDs must be updated in `karpenter-nodepool.yaml` before deploying NodePool
- All IAM policy creation must be done via AWS Console with admin account, as `eks-user` lacks `iam:CreatePolicy` permission