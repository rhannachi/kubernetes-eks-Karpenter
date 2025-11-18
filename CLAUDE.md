# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates **Kubernetes Autoscaling with Karpenter on AWS EKS**. It provides a complete setup for:
- Creating an AWS EKS (Elastic Kubernetes Service) cluster
- Installing and configuring Karpenter (cluster autoscaler)
- Setting up Horizontal Pod Autoscaler (HPA) for automatic pod scaling
- Testing and monitoring the autoscaling behavior

### Key Components
- **EKS Cluster**: Kubernetes on AWS with 2 system nodes (t3.medium)
- **Karpenter**: Open-source Kubernetes autoscaler for dynamic node provisioning
- **HPA**: Horizontal Pod Autoscaler for automatic pod scaling
- **Test Application**: PHP-Apache with load generator for testing

### Repository
- **URL**: https://github.com/rhannachi/kubernetes-eks-Karpenter
- **Branch**: master
- **Language**: YAML, Bash, JSON (Infrastructure as Code)

---

## Directory Structure

```
kubernetes-eks-Karpenter/
├── README.md                                 # Main project overview
├── README-aws-user.md                       # Step 1: AWS user setup and IAM configuration
├── README-aws-cluster.md                    # Step 2: EKS cluster creation
├── README-aws-karpenter.md                  # Step 3: Karpenter installation
├── README-aws-test.md                       # Step 4: Testing and verification
├── README-minikube.md                       # Local testing with Minikube
│
├── infra/                                   # Infrastructure configuration
│   ├── cluster.yaml                         # EKS cluster definition (eksctl format)
│   ├── karpenter-nodepool.yaml             # Karpenter NodePool and EC2NodeClass config
│   ├── karpenter-node-trust-policy.json    # IAM trust policy for Karpenter nodes
│   ├── karpenter-controller-policy.json    # IAM policy for Karpenter controller (generated)
│   └── metric-server.yaml                   # Metrics Server deployment for HPA
│
├── k8s/                                     # Kubernetes manifests
│   ├── base/                                # Base Kustomize resources
│   │   ├── kustomization.yaml              # Kustomize configuration
│   │   ├── deployment.yaml                  # PHP-Apache deployment with CPU requests/limits
│   │   └── hpa.yaml                         # Horizontal Pod Autoscaler configuration
│   │
│   └── utils/                               # Utility manifests
│       ├── test-karpenter-scaling.yaml     # Load generator for testing Karpenter
│       ├── test-minikube-scaling.yaml      # Load generator for Minikube testing
│       └── dashboard-admin.yaml             # Kubernetes dashboard admin user
│
├── verify-step1.sh                          # Verify IAM and Karpenter prerequisites
├── cleanup-karpenter.sh                     # Clean up and uninstall Karpenter
├── karpenter_cluster_monitor.sh             # Real-time cluster monitoring dashboard
│
└── images/                                  # Documentation images
    └── img.png
```

---

## Quick Start Commands

### Prerequisites
- AWS Account with appropriate IAM permissions
- AWS CLI, eksctl, kubectl, helm installed locally
- Enough AWS quota for EKS cluster and EC2 instances

### Three-Step Setup

#### Step 1: Create AWS User and IAM Configuration
```bash
# See README-aws-user.md for detailed setup
# Key outcomes:
# - Create IAM user 'eks-user' with access keys
# - Create group 'eks-user-group' with EKS permissions
# - Create custom 'EKSAdminPolicy' for secure access
# - Attach 5 policies to the group
```

#### Step 2: Create EKS Cluster
```bash
# Create cluster with system nodes
eksctl create cluster -f ./infra/cluster.yaml
# Takes ~15-20 minutes

# Deploy metrics-server for HPA
kubectl apply -f infra/metric-server.yaml
```

#### Step 3: Install Karpenter
```bash
# 1. Create IAM service account for Karpenter
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 2. Create Karpenter policy via AWS Console (must be done manually by admin)
# Policy file: infra/karpenter-controller-policy.json

# 3. Create service account
kubectl create namespace karpenter
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --name=karpenter \
  --namespace=karpenter \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME} \
  --approve \
  --override-existing-serviceaccounts

# 4. Create node role
aws iam create-role \
  --role-name KarpenterNodeRole-${CLUSTER_NAME} \
  --assume-role-policy-document file://infra/karpenter-node-trust-policy.json

# 5. Install Karpenter via Helm
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.8.2 \
  --namespace karpenter \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set controller.resources.requests.cpu=500m \
  --set controller.resources.requests.memory=512Mi \
  --wait

# 6. Deploy NodePool
kubectl apply -f infra/karpenter-nodepool.yaml

# Verify with:
./verify-step1.sh
```

#### Step 4: Deploy Test Application and Monitor
```bash
# Deploy PHP-Apache app with HPA
kubectl apply -k ./k8s/base

# Monitor HPA scaling
kubectl get hpa -w

# Monitor nodes
watch kubectl get nodes

# Monitor Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Use monitoring script
./karpenter_cluster_monitor.sh
```

---

## Common Commands

### Cluster Information
```bash
# Show cluster status
kubectl get nodes
kubectl get nodes --show-labels
kubectl describe nodes

# Metrics
kubectl top nodes
kubectl top pods -A

# Check EKS cluster details
aws eks describe-cluster --name microservices-demo-cluster --region us-east-1
```

### Karpenter Operations
```bash
# Verify Karpenter installation
kubectl get pods -n karpenter
kubectl get crd | grep karpenter
kubectl get nodepool
kubectl get ec2nodeclass
kubectl describe nodepool default

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check provisioned nodes
kubectl get nodes -L karpenter.sh/nodepool
```

### Testing and Load Generation
```bash
# Deploy test application
kubectl apply -k ./k8s/base

# Generate load
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Then in the pod shell:
while true; do wget -q -O- http://php-apache; done

# Watch HPA respond
kubectl get hpa -w
kubectl get pods -l app=php-apache -w

# Get deployment details
kubectl describe deployment php-apache
```

### Cleanup and Maintenance
```bash
# Clean up Karpenter resources
./cleanup-karpenter.sh

# Delete specific resources
kubectl delete deployment php-apache
kubectl delete hpa php-apache-hpa
kubectl delete nodepool default

# Full cluster deletion (AWS resources incur charges!)
eksctl delete cluster -f ./infra/cluster.yaml
```

---

## Architecture Explanation

### EKS Cluster Design
- **2 System Nodes** (t3.medium, static): Host critical components (metrics-server, coredns, karpenter)
- **Taint**: `CriticalAddonsOnly=true:NoSchedule` prevents regular workloads from running on system nodes
- **OIDC**: Enabled for IAM Roles for Service Accounts (IRSA) - allows pods to assume IAM roles
- **Tags**: `karpenter.sh/discovery` allows Karpenter to auto-discover VPC, subnets, and security groups

### Karpenter Architecture
- **NodePool**: Defines desired node configuration (instance types, capacity type: on-demand/spot)
- **EC2NodeClass**: AWS-specific configuration (AMI, subnets, security groups, IAM role)
- **NodeClaim**: Represents a request for a node (created when pods can't be scheduled)
- **Consolidation**: Automatically terminates underutilized nodes (WhenEmptyOrUnderutilized policy)

### Horizontal Pod Autoscaler (HPA)
- **Target**: PHP-Apache Deployment
- **Metric**: CPU utilization threshold of 50%
- **CPU Request**: 200m (0.2 cores) - this is the baseline for 100%
- **Range**: 1-10 replicas
- **Calculation**: If actual CPU > 50% of request (200m), scale up

### Scaling Flow
1. Load increases → Pod CPU usage increases
2. Metrics-server reports high CPU utilization (>50% of 200m request)
3. HPA creates additional pods
4. If no node has capacity, HPA marks pods as Pending
5. Karpenter detects Pending pods and provisions new node(s)
6. Pods are scheduled on new nodes
7. When load decreases, HPA reduces pods → Karpenter removes idle nodes

---

## Important Concepts

### IAM Security Model
The project uses a **least-privilege** security model:
- **EKSAdminPolicy**: Custom policy for user to manage EKS cluster (not AdministratorAccess)
- **KarpenterControllerPolicy**: Minimal permissions for Karpenter controller
- **KarpenterNodeRole**: Permissions for provisioned EC2 instances

### Configuration Files

#### infra/cluster.yaml (eksctl)
- Defines EKS cluster and initial node group
- Sets OIDC provider for IRSA
- Configures VPC, subnets, and security groups
- Enables CloudWatch logging

#### infra/karpenter-nodepool.yaml
- **NodePool**: Defines scaling limits (CPU: 100 cores max)
- **EC2NodeClass**: References subnets/security groups by tags
- **Consolidation**: Cleans up underutilized nodes after 1 minute

#### k8s/base/deployment.yaml
- Uses `k8s.gcr.io/hpa-example` (PHP+Apache image)
- **CPU Request**: 200m (required for HPA calculations)
- **CPU Limit**: 500m (hard limit for the container)

#### k8s/base/hpa.yaml
- Autoscales based on CPU utilization (>50%)
- Range: 1-10 pods (min-max replicas)
- Uses Kubernetes metrics API (requires metrics-server)

### Environment Variables (typically needed)
```bash
CLUSTER_NAME="microservices-demo-cluster"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

---

## Troubleshooting Guide

### Issue: Karpenter pods in CrashLoopBackOff
**Symptoms**: `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Causes**:
1. Service account namespace mismatch (created in kube-system but Karpenter runs in karpenter)
2. Trust policy references wrong namespace/service account

**Solution**:
```bash
# Verify service account is in correct namespace
kubectl get sa karpenter -n karpenter

# Check trust policy has correct namespace
aws iam get-role --role-name karpenter-${CLUSTER_NAME}
# Should have: "system:serviceaccount:karpenter:karpenter"
```

### Issue: HPA not scaling (showing 0% metrics)
**Cause**: Metrics-server not running or not reporting metrics

**Solution**:
```bash
# Check metrics-server status
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check if metrics are available
kubectl top nodes
kubectl top pods

# Redeploy metrics-server if needed
kubectl apply -f infra/metric-server.yaml
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s
```

### Issue: Karpenter not creating nodes
**Cause**: NodePool not ready, AMI ID invalid, or insufficient permissions

**Solution**:
```bash
# Check NodePool status
kubectl describe nodepool default

# Check EC2NodeClass
kubectl describe ec2nodeclass default

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Verify AMI is valid
aws ec2 describe-images --image-ids ami-xxxxxxx --region us-east-1
```

### Issue: Permission denied errors from Karpenter
**Cause**: IAM policy missing required permissions

**Common missing permissions**:
- `iam:ListInstanceProfiles`
- `iam:GetInstanceProfile`
- `sqs:ReceiveMessage` (for interruption handling)

**Solution**: Update the Karpenter IAM policy in AWS Console with missing permissions

### Issue: Nodes not terminating (consolidation not working)
**Cause**: Nodes not marked as underutilized or consolidation policy misconfigured

**Solution**:
```bash
# Check consolidation settings
kubectl describe nodepool default

# Monitor node utilization
kubectl top nodes

# Check for pod disruption budget constraints
kubectl get pdb -A
```

---

## Performance & Cost Considerations

### Optimization Tips
1. **Instance Types**: NodePool configured for t3.medium/large (good balance)
2. **Consolidation**: Enabled with 1m threshold to reduce costs
3. **On-Demand Only**: Current config uses on-demand; consider adding spot instances for cost savings
4. **CPU Limits**: Set realistic limits to prevent waste (deployment uses 500m limit for 200m request)

### Cost Monitoring
- **System Nodes**: Always running (2x t3.medium) - fixed cost
- **Dynamic Nodes**: Created on-demand, terminated when unused
- **Data Transfer**: EKS + EC2 may have data transfer costs

### AWS Free Tier
- EKS cluster management: FREE for first 750 hours/month
- EC2 instances: Subject to free tier (t3.micro/small eligible)
- Outbound data transfer: First 100GB/month free

---

## Development Workflow

### Making Changes to Deployment
```bash
# Modify k8s/base/deployment.yaml or hpa.yaml
vim k8s/base/deployment.yaml

# Apply changes
kubectl apply -k ./k8s/base

# Verify
kubectl rollout status deployment/php-apache
kubectl get hpa -w
```

### Testing New Configuration
```bash
# Apply new NodePool config
kubectl apply -f infra/karpenter-nodepool.yaml

# Verify
kubectl describe nodepool default

# Monitor provisioning
watch kubectl get nodes
```

### Upgrading Karpenter
```bash
# Check current version
helm list -n karpenter

# Upgrade (update version number)
helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.9.0 \
  --namespace karpenter \
  --wait

# Verify
kubectl get pods -n karpenter
```

---

## Testing Procedures

### Manual Load Testing
1. Deploy application: `kubectl apply -k ./k8s/base`
2. Generate load: `kubectl run -it --rm load-generator --image=busybox /bin/sh`
3. In pod shell: `while true; do wget -q -O- http://php-apache; done`
4. Monitor: Open 3 terminals:
   - Terminal 1: `kubectl get hpa -w`
   - Terminal 2: `watch kubectl get nodes`
   - Terminal 3: `./karpenter_cluster_monitor.sh`

### Expected Behavior
1. Initial state: 1 pod, 2 nodes (system only)
2. Load starts: HPA detects high CPU
3. HPA scales up pods: Replicas increase (1 → 2 → 3 → ...)
4. Nodes capacity full: Karpenter provisions new node
5. New node joins: Additional pods schedule on it
6. Load stops: HPA scales down (takes ~5 minutes)
7. Nodes consolidate: Karpenter removes empty nodes

### Verification Scripts
```bash
# Run all verifications
./verify-step1.sh

# Check all components
kubectl get nodes
kubectl get pods -A
kubectl get hpa
kubectl describe nodepool default
```

---

## Git Workflow

### Current Status
- **Branch**: master (main)
- **Latest Commits**: Focus on Karpenter AWS implementation
- **Repository**: Private (requires SSH key)

### Common Git Operations
```bash
# Check status
git status

# View logs
git log --oneline -10

# Create feature branch (if needed)
git checkout -b feature/new-feature

# Commit changes
git add .
git commit -m "Description of changes"

# Push
git push origin feature/new-feature
```

---

## Useful Resources

### Documentation Links
- [Karpenter Official Docs](https://karpenter.sh/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [eksctl Documentation](https://eksctl.io/)

### Monitoring & Observability
- **Karpenter Logs**: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f`
- **Cluster Events**: `kubectl get events -A`
- **Node Status**: `kubectl describe nodes`
- **Pod Status**: `kubectl describe pod <pod-name>`
- **HPA Status**: `kubectl describe hpa php-apache-hpa`

### AWS Console Checks
- **EKS Clusters**: https://console.aws.amazon.com/eks/home
- **EC2 Instances**: https://console.aws.amazon.com/ec2/v2/home
- **IAM Roles**: https://console.aws.amazon.com/iam/home#/roles
- **CloudWatch Logs**: EKS cluster logs (if enabled)

---

## For Future Claude Code Users

### Tips for Efficient Development
1. **Read README files in order**: They follow logical setup steps
2. **Use verification scripts**: Run `verify-step1.sh` to validate prerequisites
3. **Monitor in real-time**: Run `karpenter_cluster_monitor.sh` during tests
4. **Check logs first**: Karpenter logs reveal most issues quickly
5. **Understand the architecture**: This project demonstrates production patterns

### Common Customizations
- **Change instance types**: Edit `infra/karpenter-nodepool.yaml` (values: t3.medium, t3.large)
- **Adjust scaling limits**: Edit `k8s/base/hpa.yaml` (minReplicas, maxReplicas, averageUtilization)
- **Add spot instances**: Add to NodePool requirements (cost optimization)
- **Change application**: Replace PHP-Apache with any containerized app in `k8s/base/deployment.yaml`

### Cost-Saving Measures
- Use spot instances: Add to NodePool capacity types (70% cheaper)
- Adjust consolidation: Reduce consolidateAfter time for aggressive cleanup
- Right-size instances: Start with t3.micro/small for testing
- Set CPU limits: Prevent resource waste in containers

---

## Project Contact & Support

- **Repository**: https://github.com/rhannachi/kubernetes-eks-Karpenter
- **Issues**: Check GitHub Issues for known problems
- **Documentation**: See README-*.md files for detailed guides
- **Troubleshooting**: Refer to troubleshooting section above

---

**Last Updated**: 2025-11-18
**Project Status**: Active (Karpenter AWS implementation)
- Always use descriptive variable names
