#!/bin/bash

echo "🔍 Surveillance de Karpenter - Ctrl+C pour arrêter"
echo "=================================================="

while true; do
  clear
  echo "📊 === ÉTAT DU CLUSTER ==="
  echo ""
  
  echo "🖥️  Nœuds Kubernetes:"
  kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,INSTANCE:.spec.providerID,AGE:.metadata.creationTimestamp
  echo ""
  
  echo "📦 NodeClaims (Karpenter):"
  kubectl get nodeclaim 2>/dev/null || echo "Aucun NodeClaim"
  echo ""
  
  echo "🔢 Statistiques:"
  TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
  READY_NODES=$(kubectl get nodes --no-headers | grep -c Ready)
  PENDING_PODS=$(kubectl get pods -A --no-headers | grep -c Pending)
  RUNNING_PODS=$(kubectl get pods -A --no-headers | grep -c Running)
  
  echo "  - Nœuds totaux: $TOTAL_NODES"
  echo "  - Nœuds Ready: $READY_NODES"
  echo "  - Pods Pending: $PENDING_PODS"
  echo "  - Pods Running: $RUNNING_PODS"
  echo ""
  
  echo "📋 Derniers événements Karpenter:"
  kubectl get events -n karpenter --sort-by=.lastTimestamp | tail -5
  echo ""
  
  echo "⏱️  Mise à jour dans 5 secondes..."
  sleep 5
done
