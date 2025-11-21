# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a tutorial project demonstrating Kubernetes autoscaling on AWS EKS using **Karpenter** (v1.8.2) and HPA (Horizontal Pod Autoscaler). The project provides step-by-step instructions (in French) for setting up an EKS cluster with two-level autoscaling: pod-level via HPA and node-level via Karpenter.

**Architecture Pattern:**
- **Static System Nodes**: 2 t3.medium nodes (managed by EKS/eksctl) running Karpenter controller, metrics-server, and core services
- **Dynamic Application Nodes**: On-demand t3.medium/t3.large nodes (managed by Karpenter) for application workloads
- **Separation via Taints**: System nodes have `CriticalAddonsOnly=true:NoSchedule` taint to prevent application pods from scheduling on them
- **Kubernetes Version**: 1.34 (configured in `infra/cluster.yaml`)

## Prerequisites

Before working with this project, ensure you have the following tools installed:

- **AWS CLI** (version 2.x recommended) - for AWS resource management
- **kubectl** (version 1.23+) - for Kubernetes cluster interaction
- **eksctl** (version 0.214.0+) - for EKS cluster creation and management
- **Helm** (version 3.8+) - for Karpenter installation
- **AWS Account** with appropriate IAM permissions

Verify your setup:
```bash
aws --version
kubectl version --client
eksctl version
helm version
```

## Key Configuration Variables

These environment variables are used throughout the setup scripts and must be consistent:

```bash
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify configuration
echo "Cluster: ${CLUSTER_NAME}, Region: ${AWS_REGION}, Account: ${AWS_ACCOUNT_ID}"
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
- **Consolidation Status**: Currently configured with conservative settings for testing
  - Default (commented): `WhenEmptyOrUnderutilized` after 1 minute (aggressive consolidation)
  - Current: `WhenEmpty` after 10 minutes (conservative for stability during testing)
  - See comments in `infra/karpenter-nodepool.yaml` for switching between modes

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

## Setup Workflow Overview

The full setup process follows these steps (see detailed French documentation in README-aws-*.md files):

1. **Step 1 (README-aws-user.md)**: Create AWS IAM user and configure CLI
   - Creates `eks-user` with minimal permissions
   - Sets up AWS credentials and profile

2. **Step 2 (README-aws-cluster.md)**: Create EKS cluster
   - Uses `eksctl` to provision cluster from `infra/cluster.yaml`
   - Creates 2 static system nodes with `CriticalAddonsOnly` taint
   - Enables OIDC provider for IRSA (required for Karpenter)
   - Takes 15-20 minutes

3. **Step 3 (README-aws-karpenter.md)**: Install Karpenter and configure node provisioning
   - **⚠️ Critical**: Create IAM policy via AWS Console with admin account (cli user lacks permission)
   - Create IRSA service account binding
   - Install Karpenter via Helm (v1.8.2)
   - Deploy NodePool and EC2NodeClass configurations
   - **Must update AMI ID** in `infra/karpenter-nodepool.yaml` before applying

4. **Step 4 (README-aws-karpenter-autoscaling-test.md)**: Deploy demo app and test autoscaling
   - Deploy php-apache application with HPA
   - Generate load to test two-level autoscaling
   - Monitor pod and node scaling behavior

5. **Step 5 (README-aws-cleanup.md)**: Cleanup and resource deletion
   - Removes cluster, IAM roles, and all AWS resources
   - Important for cost management

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

## Key Implementation Details

### Kustomize Structure
The demo application uses Kustomize for deployment:
- `k8s/base/kustomization.yaml`: Lists resources (deployment.yaml and hpa.yaml)
- Deploy using: `kubectl apply -k ./k8s/base`
- This approach allows easy extension with overlays for different environments

### Metrics Server Dependency
HPA requires metrics-server to function:
- Installed as part of the Karpenter setup process (see `infra/metric-server.yaml`)
- Required for CPU and memory-based autoscaling decisions
- Monitor with: `kubectl get pods -n kube-system -l k8s-app=metrics-server`
- Allow 2-3 minutes for metrics to become available after cluster creation

### IAM Policy Requirements vs Permissions
- **IAM Policy Creation**: Requires AWS Console access with admin account (not delegable to regular users)
- **IAM Service Account Creation**: Can be done via `eksctl create iamserviceaccount` from CLI
- **Policy File Format**: JSON files in `infra/` contain placeholder variables (`${AWS_REGION}`, `${AWS_ACCOUNT_ID}`, `${CLUSTER_NAME}`)
  - These MUST be substituted via `sed` before usage
  - Example: `sed -i "s/\${CLUSTER_NAME}/${CLUSTER_NAME}/g" infra/karpenter-controller-policy.json`

## Testing Scenarios

The project is designed to demonstrate:
1. **HPA scaling**: Pods scale from 1 to 10 replicas under load
2. **Karpenter node provisioning**: New nodes automatically added when pods are pending
3. **Node consolidation**: Nodes removed when underutilized (depends on consolidation policy)
4. **Cost optimization**: On-demand instances with efficient resource packing

## Quick Reference: Common Debugging Commands

```bash
# Check cluster readiness
kubectl get nodes -o wide
kubectl get pods -A

# Monitor Karpenter activity
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check resource requests on pods (important for HPA)
kubectl describe pod <pod-name> | grep -A5 "Requests"

# Verify node selection and taints
kubectl describe node <node-name> | grep -E "Taint|Label"

# Watch autoscaling in real-time
watch -n 1 'kubectl get hpa && echo "---" && kubectl get nodes'
```
