#!/bin/bash
# =============================================================
# Desinstalador de Prometheus + Grafana para OPA Gatekeeper
# =============================================================
set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"

echo "[INFO] Desinstalando kube-prometheus-stack..."
helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || echo "[WARN] Release no encontrado, continuando..."

echo "[INFO] Eliminando PersistentVolume de Prometheus..."
kubectl delete pv prometheus-storage 2>/dev/null || true

echo "[INFO] Eliminando CRDs de Prometheus Operator..."
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd alertmanagers.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd podmonitors.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd probes.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd prometheuses.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd prometheusrules.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd servicemonitors.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd thanosrulers.monitoring.coreos.com 2>/dev/null || true

echo "[INFO] Eliminando ServiceMonitor de Gatekeeper..."
kubectl delete service gatekeeper-controller-manager-metrics-service -n gatekeeper-system 2>/dev/null || true

echo "[INFO] Eliminando PersistentVolumeClaims..."
kubectl delete pvc -n $NAMESPACE --all 2>/dev/null || true

echo "[INFO] Eliminando PersistentVolumes huérfanos..."
kubectl get pv | grep $NAMESPACE | awk '{print $1}' | xargs -r kubectl delete pv 2>/dev/null || true

echo "[INFO] Esperando a que los recursos se eliminen..."
sleep 5

echo "[INFO] Eliminando namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE 2>/dev/null || echo "[WARN] Namespace ya eliminado"

echo "[INFO] Limpiando archivos de configuración locales..."
rm -f values-monitoring.yaml 2>/dev/null || true

echo ""
echo "✅ Desinstalación completada correctamente"
echo "==========================================="
echo "🗑️  Componentes eliminados:"
echo "   - Helm release: $RELEASE_NAME"
echo "   - Namespace: $NAMESPACE"
echo "   - CRDs de Prometheus Operator"
echo "   - ServiceMonitor de Gatekeeper"
echo "   - PVCs y PVs"
echo "==========================================="
