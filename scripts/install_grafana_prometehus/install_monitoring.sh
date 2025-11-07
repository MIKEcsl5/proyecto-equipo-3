#!/bin/bash
# =============================================================
# Instalador de Prometheus + Grafana para monitoreo de OPA Gatekeeper
# =============================================================
set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"

echo "[INFO] Creando namespace $NAMESPACE (si no existe)..."
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create ns $NAMESPACE

echo "[INFO] Instalando Helm si no está disponible..."
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "[INFO] Agregando repositorio Helm de Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "[INFO] Creando archivo values-monitoring.yaml..."
cat <<EOF > values-monitoring.yaml
# Configuración de Grafana
grafana:
  adminUser: admin
  adminPassword: prom-operator
  service:
    type: NodePort
    nodePort: 32000
  
  # Deshabilitar persistencia del chart y usar hostPath directamente
  persistence:
    enabled: false
  
  # Montar /opt como volumen de datos
  extraVolumes:
  - name: storage
    hostPath:
      path: /opt
      type: DirectoryOrCreate
  
  extraVolumeMounts:
  - name: storage
    mountPath: /var/lib/grafana
    subPath: grafana
  
  # Dashboards preconfigurados para OPA Gatekeeper
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
  
  dashboards:
    default:
      gatekeeper:
        gatesource: https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/grafana/gatekeeper-dashboard.json

# Configuración de Alertmanager (deshabilitado)
alertmanager:
  enabled: false

# Configuración de Prometheus
prometheus:
  service:
    type: NodePort
    nodePort: 32001
  
  prometheusSpec:
    # Retención de datos
    retention: 15d
    
    # Almacenamiento con hostPath
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
          selector:
            matchLabels:
              app: prometheus-storage
    
    # ServiceMonitor para OPA Gatekeeper
    additionalServiceMonitors:
    - name: gatekeeper-controller-manager
      selector:
        matchLabels:
          control-plane: controller-manager
          gatekeeper.sh/system: "yes"
      namespaceSelector:
        matchNames:
        - gatekeeper-system
      endpoints:
      - port: metrics
        interval: 30s
        path: /metrics

# Configuración de Node Exporter
prometheus-node-exporter:
  enabled: true
  hostRootFsMount:
    enabled: true
  service:
    port: 9100
    targetPort: 9100

# Kube State Metrics
kube-state-metrics:
  enabled: true

# Prometheus Operator
prometheusOperator:
  enabled: true
EOF

echo "[INFO] Limpiando PersistentVolume existente si existe..."
kubectl delete pv prometheus-storage 2>/dev/null || true
sleep 2

echo "[INFO] Creando PersistentVolume para Prometheus..."
cat <<PVEOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-storage
  labels:
    app: prometheus-storage
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /opt
    type: DirectoryOrCreate
  persistentVolumeReclaimPolicy: Retain
PVEOF

echo "[INFO] Instalando kube-prometheus-stack..."
helm install $RELEASE_NAME prometheus-community/kube-prometheus-stack \
  -n $NAMESPACE \
  -f values-monitoring.yaml

echo "[INFO] Esperando a que los pods estén listos..."
kubectl wait --for=condition=available --timeout=600s deployment -n $NAMESPACE --all

echo "[INFO] Configurando ServiceMonitor para Gatekeeper..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-controller-manager-metrics-service
  namespace: gatekeeper-system
  labels:
    control-plane: controller-manager
    gatekeeper.sh/system: "yes"
spec:
  ports:
  - name: metrics
    port: 8888
    protocol: TCP
    targetPort: 8888
  selector:
    control-plane: controller-manager
    gatekeeper.sh/operation: webhook
EOF

echo ""
echo "✅ Instalación completada correctamente"
echo "==========================================="
echo "📊 Grafana:     http://<NODE-IP>:32000"
echo "📈 Prometheus:  http://<NODE-IP>:32001"
echo ""
echo "🔐 Credenciales Grafana:"
echo "   Usuario:     admin"
echo "   Contraseña:  prom-operator"
echo ""
echo "📋 Métricas disponibles de OPA Gatekeeper:"
echo "   - gatekeeper_constraints"
echo "   - gatekeeper_constraint_templates"
echo "   - gatekeeper_violations"
echo "   - gatekeeper_webhook_request_count"
echo "   - gatekeeper_webhook_request_duration_seconds"
echo ""
echo "🎯 Para ver las métricas en Prometheus:"
echo "   1. Accede a Prometheus (puerto 32001)"
echo "   2. Busca métricas que empiecen con 'gatekeeper_'"
echo ""
echo "📊 Dashboard de Grafana:"
echo "   El dashboard de Gatekeeper se importará automáticamente"
echo "==========================================="
