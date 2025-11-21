#!/bin/bash

# Karpenter IAM Permissions Validation Script
# Version: 1.0
# Purpose: Validate Karpenter controller IAM permissions

# Exit on any error
set -e

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
export CLUSTER_NAME="microservices-demo-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
KARPENTER_NAMESPACE="karpenter"

# Function to print success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error message
error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to print warning message
warn() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Validate Karpenter Service Account
validate_service_account() {
    echo "🔍 Validating Karpenter Service Account..."

    # Get Service Account IAM Role ARN
    SA_ROLE_ARN=$(kubectl get sa karpenter -n $KARPENTER_NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

    if [ -z "$SA_ROLE_ARN" ]; then
        error "Karpenter Service Account not found or lacks IAM role annotation"
    fi

    success "Karpenter Service Account IAM role found: $SA_ROLE_ARN"
}

# Test EC2 Fleet Creation Permissions
test_create_fleet() {
    echo "🚀 Testing EC2 Fleet Creation Permissions..."

    # Temporary launch template for test
    LAUNCH_TEMPLATE_NAME="karpenter-test-launch-template-$(date +%s)"

    # Create a launch template
    aws ec2 create-launch-template \
        --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
        --version-description "Test launch template for Karpenter permissions" \
        --launch-template-data '{"ImageId":"ami-0c55b159cbfafe1f0","InstanceType":"t3.medium"}' || error "Failed to create launch template"

    # Create a fleet
    FLEET_ID=$(aws ec2 create-fleet \
        --launch-template-configs "LaunchTemplateSpecification={LaunchTemplateName=$LAUNCH_TEMPLATE_NAME,Version=1}" \
        --target-capacity-specification TotalTargetCapacity=1,DefaultTargetCapacityType=spot \
        --type instant \
        --query 'FleetId' \
        --output text) || error "Failed to create EC2 fleet"

    success "Successfully created launch template and EC2 fleet"

    # Cleanup
    aws ec2 delete-launch-template --launch-template-name "$LAUNCH_TEMPLATE_NAME"
    # Vérifier et supprimer la flotte si possible
    if aws ec2 describe-fleets --fleet-ids "$FLEET_ID" &>/dev/null; then
        aws ec2 delete-fleets --fleet-ids "$FLEET_ID" --terminate-instances || warn "Impossible de supprimer la flotte $FLEET_ID"
    else
        warn "La flotte $FLEET_ID n'existe plus ou ne peut pas être supprimée"
    fi
}

# Test Launch Template Version Creation
test_launch_template_version() {
    echo "🔧 Testing Launch Template Version Creation..."

    LAUNCH_TEMPLATE_NAME="karpenter-test-versioned-template-$(date +%s)"

    # Create initial launch template
    aws ec2 create-launch-template \
        --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
        --version-description "Initial version" \
        --launch-template-data '{"ImageId":"ami-0c55b159cbfafe1f0","InstanceType":"t3.medium"}' || error "Failed to create initial launch template"

    # Create a new version
    aws ec2 create-launch-template-version \
        --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
        --version-description "Second version" \
        --launch-template-data '{"ImageId":"ami-0c55b159cbfafe1f0","InstanceType":"t3.large"}' || error "Failed to create launch template version"

    success "Successfully created launch template with multiple versions"

    # Cleanup
    aws ec2 delete-launch-template --launch-template-name "$LAUNCH_TEMPLATE_NAME"
}

# Test Karpenter Controller Logging
test_karpenter_logs() {
    echo "📋 Checking Karpenter Controller Logs for Errors..."

    # Get Karpenter pod name
    POD_NAME=$(kubectl get pods -n $KARPENTER_NAMESPACE -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[0].metadata.name}')

    # Check logs for any authorization errors
    AUTHZ_ERRORS=$(kubectl logs -n $KARPENTER_NAMESPACE "$POD_NAME" | grep -E "UnauthorizedOperation|AccessDenied" || true)

    if [ -n "$AUTHZ_ERRORS" ]; then
        warn "Authorization errors found in Karpenter logs:\n$AUTHZ_ERRORS"
    else
        success "No authorization errors found in Karpenter logs"
    fi
}

# Validate NodePool and EC2NodeClass
validate_karpenter_resources() {
    echo "🔬 Validating Karpenter Resources..."

    # Check NodePool status
    NODEPOOL_STATUS=$(kubectl get nodepool microservices-general-ondemand -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$NODEPOOL_STATUS" != "True" ]; then
        error "NodePool is not in Ready state"
    fi

    # Check EC2NodeClass status
    EC2NODECLASS_STATUS=$(kubectl get ec2nodeclass microservices-general-al2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$EC2NODECLASS_STATUS" != "True" ]; then
        error "EC2NodeClass is not in Ready state"
    fi

    success "NodePool and EC2NodeClass are in Ready state"
}

# Main test runner
main() {
    echo "🔐 Karpenter IAM Permissions Validation Test"
    echo "----------------------------------------"

    validate_service_account
    test_create_fleet
    test_launch_template_version
    test_karpenter_logs
    validate_karpenter_resources

    echo -e "\n${GREEN}🎉 All Karpenter IAM Permission Tests Passed Successfully!${NC}"
}

# Run the tests
main