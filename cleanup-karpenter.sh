#!/bin/bash

echo "======================================"
echo "🧹 NETTOYAGE DE KARPENTER"
echo "======================================"
echo ""

echo "1️⃣  Suppression des NodePools et EC2NodeClass..."
kubectl delete nodepool --all 2>/dev/null
kubectl delete ec2nodeclass --all 2>/dev/null
echo "   ✅ Fait"
echo ""

echo "2️⃣  Désinstallation de Karpenter via Helm..."
helm uninstall karpenter -n karpenter 2>/dev/null
if [ $? -eq 0 ]; then
  echo "   ✅ Karpenter désinstallé"
else
  echo "   ⚠️  Karpenter n'était pas installé via Helm ou déjà supprimé"
fi
echo ""

echo "3️⃣  Attente de la suppression des ressources (30s)..."
sleep 30
echo ""

echo "4️⃣  Suppression du namespace karpenter..."
kubectl delete namespace karpenter --timeout=60s 2>/dev/null
echo "   ✅ Fait"
echo ""

echo "5️⃣  Suppression des CRDs Karpenter..."
kubectl delete crd nodepools.karpenter.sh 2>/dev/null
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws 2>/dev/null
kubectl delete crd nodeclaims.karpenter.sh 2>/dev/null
echo "   ✅ Fait"
echo ""

echo "6️⃣  Vérification finale..."
REMAINING=$(kubectl get all -n karpenter 2>/dev/null | wc -l)
CRDS=$(kubectl get crd | grep karpenter | wc -l)

if [ "$REMAINING" -eq 0 ] && [ "$CRDS" -eq 0 ]; then
  echo "   ✅ Karpenter complètement supprimé !"
else
  echo "   ⚠️  Il reste des ressources:"
  kubectl get all -n karpenter 2>/dev/null
  kubectl get crd | grep karpenter 2>/dev/null
fi

echo ""
echo "======================================"
echo "✅ NETTOYAGE TERMINÉ"
echo "======================================"
