#!/bin/bash

# Strict mode
set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}✔ $1${NC}"
}

# Warning function
warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Error function
error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Validate environment
validate_env() {
    if [ -z "${CLUSTER_NAME:-}" ]; then
        error "CLUSTER_NAME is not set. Please set it before running this script."
    fi
}

# Karpenter Helm Release Verification
verify_helm_release() {
    echo -e "\n🔍 Vérification de la release Helm Karpenter..."

    local HELM_STATUS
    HELM_STATUS=$(helm status karpenter -n karpenter 2>&1)

    if echo "$HELM_STATUS" | grep -q "deployed"; then
        log "Release Helm Karpenter correctement déployée"
    else
        error "La release Helm Karpenter n'est pas déployée correctement"
    fi
}

# Pods Status Check
verify_karpenter_pods() {
    echo -e "\n📦 Vérification des pods Karpenter..."

    local POD_STATUS
    POD_STATUS=$(kubectl get pods -n karpenter -o json | jq -r '.items[].status.phase')

    if [[ "$POD_STATUS" =~ "Running" ]]; then
        log "Tous les pods Karpenter sont en Running"
    else
        error "Les pods Karpenter ne sont pas tous en Running"
    fi

    # Detailed pod status
    kubectl get pods -n karpenter
}

# CRDs Verification
verify_karpenter_crds() {
    echo -e "\n🧩 Vérification des Custom Resource Definitions..."

    local EXPECTED_CRDS=("ec2nodeclasses.karpenter.k8s.aws" "nodeclaims.karpenter.sh" "nodepools.karpenter.sh")

    for crd in "${EXPECTED_CRDS[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            log "CRD $crd trouvé"
        else
            error "CRD $crd manquant"
        fi
    done
}

# Logs Analysis
verify_karpenter_logs() {
    echo -e "\n📝 Analyse des logs Karpenter..."

    local LOG_ERRORS
    LOG_ERRORS=$(kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 2>&1 | grep -E "ERROR|AccessDenied|WARN")

    if [ -z "$LOG_ERRORS" ]; then
        log "Aucune erreur critique trouvée dans les logs"
    else
        warn "Erreurs potentielles dans les logs Karpenter :"
        echo "$LOG_ERRORS"
    fi
}

# IAM Role Verification
verify_karpenter_iam() {
    echo -e "\n🔐 Vérification de la configuration IAM..."

    local IAM_ROLE_ARN
    IAM_ROLE_ARN=$(kubectl get sa karpenter -n karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

    if [ -n "$IAM_ROLE_ARN" ]; then
        log "Rôle IAM Karpenter configuré : $IAM_ROLE_ARN"
    else
        error "Aucun rôle IAM trouvé pour Karpenter"
    fi
}

# Main verification function
main() {
    echo -e "🚀 Début de la vérification de l'installation Karpenter\n"

    validate_env
    verify_helm_release
    verify_karpenter_pods
    verify_karpenter_crds
    verify_karpenter_logs
    verify_karpenter_iam

    echo -e "\n✅ ${GREEN}Vérification complète de l'installation Karpenter${NC}"
}

# Run main and handle potential errors
main || exit 1