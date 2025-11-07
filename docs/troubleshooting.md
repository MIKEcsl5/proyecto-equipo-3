# OPA Gatekeeper - Guía de Troubleshooting

## Índice

1. [Problemas Comunes](#problemas-comunes)
2. [Diagnóstico](#diagnóstico)
3. [Soluciones por Política](#soluciones-por-política)
4. [Logs y Depuración](#logs-y-depuración)
5. [Rendimiento](#rendimiento)
6. [Recuperación de Desastres](#recuperación-de-desastres)

---

## Problemas Comunes

### 1. Las políticas no se aplican

**Síntomas**:
- Los recursos se crean a pesar de violar las políticas
- No se reciben mensajes de error de Gatekeeper
- Las constraints aparecen como activas pero no bloquean nada

**Diagnóstico**:

```bash
# 1. Verificar que Gatekeeper esté funcionando
kubectl get pods -n gatekeeper-system

# Salida esperada:
# NAME                                            READY   STATUS    RESTARTS   AGE
# gatekeeper-audit-xxxxxxxxxx-xxxxx              1/1     Running   0          1d
# gatekeeper-controller-manager-xxxxxxxxxx-xxxxx 1/1     Running   0          1d
# gatekeeper-controller-manager-xxxxxxxxxx-xxxxx 1/1     Running   0          1d

# 2. Verificar los webhooks
kubectl get validatingwebhookconfigurations | grep gatekeeper

# 3. Verificar que el Constraint esté activo
kubectl get constraint <nombre-constraint>
kubectl describe constraint <nombre-constraint>

# 4. Revisar logs de errores
kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=100
```

**Soluciones**:

**A. Pods de Gatekeeper no están Running**:
```bash
# Ver detalles del pod
kubectl describe pod -n gatekeeper-system <pod-name>

# Reiniciar Gatekeeper
kubectl rollout restart deployment -n gatekeeper-system gatekeeper-controller-manager
kubectl rollout restart deployment -n gatekeeper-system gatekeeper-audit
```

**B. Webhooks no configurados**:
```bash
# Reinstalar Gatekeeper
kubectl delete -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
```

**C. Constraint en modo dryrun o warn**:
```bash
# Verificar enforcementAction
kubectl get constraint <nombre> -o jsonpath='{.spec.enforcementAction}'

# Cambiar a deny
kubectl patch constraint <nombre> --type=merge -p '{"spec":{"enforcementAction":"deny"}}'
```

**D. Namespace excluido**:
```bash
# Verificar exclusiones
kubectl get constraint <nombre> -o jsonpath='{.spec.match.excludedNamespaces}'

# Editar para remover namespace
kubectl edit constraint <nombre>
```

---

### 2. Error: "no matches for kind ConstraintTemplate"

**Síntomas**:
```
error: unable to recognize "policy.yaml": no matches for kind "ConstraintTemplate" in version "templates.gatekeeper.sh/v1beta1"
```

**Causa**: Gatekeeper no está instalado o los CRDs no se crearon correctamente.

**Solución**:

```bash
# 1. Verificar si Gatekeeper está instalado
kubectl get ns gatekeeper-system

# 2. Verificar CRDs
kubectl get crd | grep gatekeeper

# Salida esperada:
# constrainttemplates.templates.gatekeeper.sh
# configs.config.gatekeeper.sh
# ...

# 3. Si no existe, instalar Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

# 4. Esperar a que los pods estén listos
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=90s
```

---

### 3. Las políticas bloquean pods del sistema

**Síntomas**:
- Pods en `kube-system` son bloqueados
- Componentes críticos del cluster no pueden iniciar
- Pods de networking o storage son rechazados

**Causa**: Las políticas se aplican a namespaces del sistema que requieren privilegios especiales.

**Solución**:

```bash
# Agregar namespaces a excludedNamespaces
kubectl edit constraint <nombre-constraint>
```

Modificar la sección `match`:

```yaml
spec:
  match:
    excludedNamespaces:
      - "kube-system"
      - "gatekeeper-system"
      - "kube-public"
      - "kube-node-lease"
      - "calico-system"
      - "istio-system"
      - "monitoring"
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

**Alternativa - Usar namespaceSelector**:

```yaml
spec:
  match:
    namespaceSelector:
      matchLabels:
        enforce-policies: "true"
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Luego etiquetar solo los namespaces donde quieres aplicar políticas:

```bash
kubectl label namespace default enforce-policies=true
kubectl label namespace production enforce-policies=true
```

---

### 4. Política 10 (PDB) no funciona

**Síntomas**:
- La política no detecta PDBs existentes
- Error: "data.inventory.namespace is undefined"
- Deployments se crean aunque no haya PDB

**Causa**: Data sync no está habilitado.

**Diagnóstico**:

```bash
# Verificar si data sync está configurado
kubectl get config -n gatekeeper-system config -o yaml

# Ver si los datos están sincronizados
kubectl get -n gatekeeper-system config config -o jsonpath='{.status.byPod}'
```

**Solución**:

```bash
# 1. Habilitar data sync
kubectl apply -f - <<EOF
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  sync:
    syncOnly:
      - group: ""
        version: "v1"
        kind: "Namespace"
      - group: "policy"
        version: "v1"
        kind: "PodDisruptionBudget"
EOF

# 2. Esperar a que se complete la sincronización (30-60 segundos)
sleep 60

# 3. Verificar sincronización
kubectl get config -n gatekeeper-system config -o jsonpath='{.status.syncOnly}'

# 4. Reiniciar pods de Gatekeeper si es necesario
kubectl rollout restart deployment -n gatekeeper-system gatekeeper-controller-manager
```

**Verificar que funciona**:

```bash
# Crear un PDB de prueba
kubectl apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: test-pdb
  namespace: production
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: test
EOF

# Intentar crear Deployment (debería funcionar)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF
```

---

### 5. Mensajes de error poco claros

**Síntomas**:
- Errores de Gatekeeper no explican claramente qué está mal
- Mensajes genéricos como "violation detected"
- Difícil identificar qué contenedor o configuración causa el problema

**Causa**: Los mensajes de error en el código Rego no son descriptivos.

**Solución**:

Editar el ConstraintTemplate y mejorar los mensajes:

```bash
kubectl edit constrainttemplate <nombre>
```

**Ejemplo - Mejorar mensaje de K8sRequiredResources**:

```rego
# ❌ Mensaje genérico
violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  not container.resources.limits
  msg := "Container missing limits"
}

# ✅ Mensaje descriptivo
violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  not container.resources.limits
  msg := sprintf("El contenedor '%v' no define resource limits. Debe especificar limits.cpu y limits.memory", [container.name])
}
```

**Mejores prácticas para mensajes**:

1. **Incluir el nombre del recurso**:
```rego
msg := sprintf("El contenedor '%v' en el Pod '%v' ...", [container.name, input.review.object.metadata.name])
```

2. **Explicar qué falta**:
```rego
msg := sprintf("Falta el label obligatorio '%v'. Labels actuales: %v", [required_label, input.review.object.metadata.labels])
```

3. **Dar ejemplos de configuración correcta**:
```rego
msg := "El contenedor debe tener readOnlyRootFilesystem: true en securityContext. Ejemplo: securityContext: { readOnlyRootFilesystem: true }"
```

---

### 6. Rendimiento degradado

**Síntomas**:
- El cluster responde lento después de aplicar políticas
- Timeout en la creación de recursos
- Alta latencia en el API server

**Diagnóstico**:

```bash
# 1. Revisar recursos de Gatekeeper
kubectl top pods -n gatekeeper-system

# 2. Ver métricas del webhook
kubectl port-forward -n gatekeeper-system svc/gatekeeper-webhook-service 8888:443
curl -k https://localhost:8888/metrics | grep webhook_request_duration

# 3. Contar constraints activos
kubectl get constraints --all-namespaces | wc -l

# 4. Ver logs de rendimiento
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep -i "slow\|timeout\|latency"
```

**Soluciones**:

**A. Aumentar recursos de Gatekeeper**:

```bash
kubectl edit deployment gatekeeper-controller-manager -n gatekeeper-system
```

```yaml
spec:
  template:
    spec:
      containers:
      - name: manager
        resources:
          limits:
            cpu: "2"
            memory: "1Gi"
          requests:
            cpu: "500m"
            memory: "512Mi"
```

**B. Optimizar políticas Rego**:

```rego
# ❌ Ineficiente - ciclo innecesario
violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  other_container := input.review.object.spec.containers[_]
  # Comparaciones O(n²)
}

# ✅ Eficiente - una iteración
violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  # Lógica directa sin ciclos anidados
}
```

**C. Limitar alcance con namespaceSelector**:

```yaml
spec:
  match:
    namespaceSelector:
      matchLabels:
        enforce-strict-policies: "true"
```

**D. Reducir número de políticas**:
- Combinar políticas similares cuando sea posible
- Eliminar políticas redundantes
- Usar políticas solo en ambientes críticos (producción)

---

### 7. Error: "webhook call failed"

**Síntomas**:
```
Error from server (InternalError): Internal error occurred: failed calling webhook "validation.gatekeeper.sh": 
Post "https://gatekeeper-webhook-service.gatekeeper-system.svc:443/v1/admit?timeout=3s": context deadline exceeded
```

**Causas posibles**:
1. Timeout del webhook muy bajo
2. Gatekeeper sobrecargado
3. Problemas de red en el cluster
4. Certificados del webhook expirados

**Soluciones**:

**A. Aumentar timeout del webhook**:

```bash
kubectl edit validatingwebhookconfiguration gatekeeper-validating-webhook-configuration
```

```yaml
webhooks:
- name: validation.gatekeeper.sh
  timeoutSeconds: 10  # Aumentar de 3 a 10 segundos
```

**B. Verificar conectividad**:

```bash
# Desde un pod de prueba
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -k https://gatekeeper-webhook-service.gatekeeper-system.svc:443/healthz
```

**C. Verificar certificados**:

```bash
kubectl get secret -n gatekeeper-system gatekeeper-webhook-server-cert -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

Si están expirados:

```bash
# Eliminar certificados para regenerarlos
kubectl delete secret -n gatekeeper-system gatekeeper-webhook-server-cert

# Reiniciar Gatekeeper
kubectl rollout restart deployment -n gatekeeper-system gatekeeper-controller-manager
```

---

## Diagnóstico

### Comandos útiles de diagnóstico

```bash
# Estado general de Gatekeeper
kubectl get all -n gatekeeper-system

# Ver todas las constraints
kubectl get constraints --all-namespaces

# Ver status de una constraint específica
kubectl describe constraint <nombre>

# Ver violaciones actuales
kubectl get constraint <nombre> -o jsonpath='{.status.violations}' | jq

# Ver templates disponibles
kubectl get constrainttemplates

# Logs del controller manager
kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=100 -f

# Logs del auditor
kubectl logs -n gatekeeper-system -l control-plane=audit-controller --tail=100 -f

# Eventos recientes de Gatekeeper
kubectl get events -n gatekeeper-system --sort-by='.lastTimestamp'

# Métricas de Gatekeeper
kubectl port-forward -n gatekeeper-system svc/gatekeeper-webhook-service 8888:443
curl -k https://localhost:8888/metrics
```

### Verificar una política específica

```bash
#!/bin/bash
CONSTRAINT_NAME="require-pod-resources"

echo "=== Estado del Constraint ==="
kubectl get constraint $CONSTRAINT_NAME

echo -e "\n=== Detalles ==="
kubectl describe constraint $CONSTRAINT_NAME

echo -e "\n=== Violaciones ==="
kubectl get constraint $CONSTRAINT_NAME -o jsonpath='{.status.violations}' | jq

echo -e "\n=== Modo de enforcement ==="
kubectl get constraint $CONSTRAINT_NAME -o jsonpath='{.spec.enforcementAction}'

echo -e "\n=== Namespaces excluidos ==="
kubectl get constraint $CONSTRAINT_NAME -o jsonpath='{.spec.match.excludedNamespaces}'
```

### Test manual de una política

```bash
# 1. Crear recurso de prueba en archivo
cat > test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-policy
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# 2. Dry-run para ver si sería bloqueado
kubectl apply -f test-pod.yaml --dry-run=server

# 3. Ver el error completo
kubectl apply -f test-pod.yaml --dry-run=server 2>&1 | tee policy-test.log

# 4. Limpiar
rm test-pod.yaml policy-test.log
```

---

## Soluciones por Política

### Política 1: K8sRequiredResources

**Problema**: "Container missing limits/requests"

**Solución**:
```yaml
spec:
  containers:
  - name: myapp
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
```

**Debugging**:
```bash
# Ver qué contenedores no tienen recursos
kubectl get pods --all-namespaces -o json | jq '.items[] | select(.spec.containers[].resources == null) | {name: .metadata.name, namespace: .metadata.namespace}'
```

---

### Política 2: K8sTrustedRegistries

**Problema**: "Image from untrusted registry"

**Solución**:
```bash
# 1. Ver registries permitidos
kubectl get constraint allowed-registries -o jsonpath='{.spec.parameters.registries}'

# 2. Agregar nuevo registry
kubectl edit constraint allowed-registries

# 3. O usar imagen de registry permitido
# Cambiar: myregistry.com/app:latest
# Por: docker.io/library/nginx:latest
```

**Casos especiales**:
- Imágenes sin registry explícito usan `docker.io` por defecto
- Tags como `:latest` se expanden a `docker.io/library/nginx:latest`

---

### Política 3: K8sRequiredLabels

**Problema**: "Missing required label 'environment'"

**Solución**:
```yaml
metadata:
  labels:
    app: myapp
    environment: production  # dev | staging | production
    owner: team-devops
    version: v1.2.3
```

**Debugging**:
```bash
# Ver labels actuales de un pod
kubectl get pod <nombre> -o jsonpath='{.metadata.labels}'

# Listar pods sin label requerido
kubectl get pods --all-namespaces -l '!environment'
```

---

### Política 4: K8sPrivilegedContainers

**Problema**: "Container running in privileged mode"

**Solución**:
```yaml
spec:
  containers:
  - name: myapp
    securityContext:
      privileged: false  # O simplemente omitir
```

**Casos legítimos que requieren privileged**:
- Agregar namespace a excludedNamespaces
- Usar DaemonSets del sistema (CNI, CSI drivers)

---

### Política 5: K8sReadOnlyRootFS

**Problema**: "Container missing readOnlyRootFilesystem"

**Solución**:
```yaml
spec:
  containers:
  - name: myapp
    securityContext:
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/myapp
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

**Directorios comunes que necesitan escritura**:
- `/tmp`
- `/var/run`
- `/var/cache`
- `/var/log` (mejor usar stdout)

---

### Política 6: K8sBlockHostPath

**Problema**: "Pod uses hostPath volume"

**Solución** - Usar alternativas:

| hostPath para | Alternativa |
|---------------|-------------|
| Datos temporales | `emptyDir: {}` |
| Datos persistentes | `persistentVolumeClaim` |
| Configuración | `configMap` |
| Secretos | `secret` |
| Socket de Docker | Evitar, usar `kubectl exec` |

**Ejemplo**:
```yaml
# ❌ hostPath
volumes:
- name: data
  hostPath:
    path: /mnt/data

# ✅ PVC
volumes:
- name: data
  persistentVolumeClaim:
    claimName: myapp-data
```

---

### Política 7: K8sSecurityContext

**Problema**: "Container running as root" o "Missing securityContext"

**Solución completa**:
```yaml
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    runAsNonRoot: true
  containers:
  - name: myapp
    securityContext:
      runAsUser: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
```

**Debugging - Ver qué usuario usa un pod**:
```bash
kubectl exec <pod-name> -- id
```

---

### Política 8: K8sNetworkPolicyLabel

**Problema**: "Pod missing network-policy label"

**Solución**:
```yaml
metadata:
  labels:
    network-policy: enabled
```

**Crear NetworkPolicy en el namespace**:
```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

---

### Política 9: K8sRequiredProbes

**Problema**: "Container missing livenessProbe/readinessProbe"

**Solución mínima**:
```yaml
spec:
  containers:
  - name: myapp
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
```

**Debugging - Test manual de health endpoint**:
```bash
kubectl port-forward pod/<pod-name> 8080:8080
curl http://localhost:8080/healthz
```

---

### Política 10: K8sRequirePDB

**Problema**: "Namespace missing PodDisruptionBudget"

**Solución**:
```bash
# 1. Crear PDB primero
kubectl apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: production
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
EOF

# 2. Luego crear el Deployment
kubectl apply -f deployment.yaml
```

**Verificar PDBs existentes**:
```bash
kubectl get pdb --all-namespaces
```

---

## Logs y Depuración

### Niveles de log

```bash
# Cambiar nivel de log de Gatekeeper
kubectl edit deployment gatekeeper-controller-manager -n gatekeeper-system
```

```yaml
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --log-level=debug  # error, warn, info, debug
```

### Logs específicos

```bash
# Solo errores
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep ERROR

# Requests bloqueados
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep "admission webhook.*denied"

# Performance issues
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep -i "slow\|timeout"

# Sincronización de datos
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep sync
```

### Habilitar audit logs detallados

```bash
kubectl edit deployment gatekeeper-audit -n gatekeeper-system
```

```yaml
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --audit-interval=60  # Segundos entre auditorías
        - --constraint-violations-limit=100  # Máximo de violaciones a reportar
        - --log-level=debug
```

---

## Rendimiento

### Monitorear métricas

```bash
# Exponer métricas
kubectl port-forward -n gatekeeper-system svc/gatekeeper-webhook-service 8888:443 &

# Latencia del webhook
curl -k https://localhost:8888/metrics | grep webhook_request_duration_seconds

# Violaciones por constraint
curl -k https://localhost:8888/metrics | grep gatekeeper_violations

# Rate de requests
curl -k https://localhost:8888/metrics | grep webhook_request_total
```

### Optimización

**1. Reducir políticas activas**:
```bash
# Cambiar a dryrun las políticas no críticas
kubectl patch constraint <nombre> --type=merge -p '{"spec":{"enforcementAction":"dryrun"}}'
```

**2. Limitar alcance**:
```yaml
spec:
  match:
    namespaceSelector:
      matchExpressions:
      - key: environment
        operator: In
        values: ["production"]
```

**3. Aumentar recursos**:
```yaml
resources:
  requests:
    cpu: "1"
    memory: "512Mi"
  limits:
    cpu: "2"
    memory: "1Gi"
```

**4. Escalar horizontalmente**:
```bash
kubectl scale deployment gatekeeper-controller-manager -n gatekeeper-system --replicas=3
```

---

## Recuperación de Desastres

### Backup de políticas

```bash
#!/bin/bash
# backup-gatekeeper.sh

BACKUP_DIR="gatekeeper-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup ConstraintTemplates
kubectl get constrainttemplates -o yaml > $BACKUP_DIR/templates.yaml

# Backup Constraints
kubectl get constraints --all-namespaces -o yaml > $BACKUP_DIR/constraints.yaml

# Backup Config
kubectl get config -n gatekeeper-system config -o yaml > $BACKUP_DIR/config.yaml

echo "Backup guardado en: $BACKUP_DIR"
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
```

### Restaurar políticas

```bash
#!/bin/bash
# restore-gatekeeper.sh

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
  echo "Uso: $0 <backup-file.tar.gz>"
  exit 1
fi

tar -xzf $BACKUP_FILE
BACKUP_DIR=$(basename $BACKUP_FILE .tar.gz)

# Restaurar en orden
kubectl apply -f $BACKUP_DIR/templates.yaml
sleep 10  # Esperar a que los templates se procesen
kubectl apply -f $BACKUP_DIR/config.yaml
sleep 5
kubectl apply -f $BACKUP_DIR/constraints.yaml

echo "Restauración completada"
```

### Rollback de política problemática

```bash
# 1. Cambiar a dryrun temporalmente
kubectl patch constraint <nombre> --type=merge -p '{"spec":{"enforcementAction":"dryrun"}}'

# 2. Revisar violaciones
kubectl get constraint <nombre> -o jsonpath='{.status.violations}'

# 3. Eliminar si es necesario
kubectl delete constraint <nombre>

# 4. Restaurar versión anterior desde backup
kubectl apply -f backup/constraints.yaml
```

### Deshabitar Gatekeeper temporalmente

```bash
# CUIDADO: Solo para emergencias

# Opción 1: Escalar a 0 (rápido)
kubectl scale deployment gatekeeper-controller-manager -n gatekeeper-system --replicas=0
kubectl scale deployment gatekeeper-audit -n gatekeeper-system --replicas=0

# Opción 2: Eliminar webhook (más seguro)
kubectl delete validatingwebhookconfiguration gatekeeper-validating-webhook-configuration

# Para reactivar:
kubectl scale deployment gatekeeper-controller-manager -n gatekeeper-system --replicas=3
kubectl scale deployment gatekeeper-audit -n gatekeeper-system --replicas=1
# O reinstalar Gatekeeper para recrear webhooks
```

---


