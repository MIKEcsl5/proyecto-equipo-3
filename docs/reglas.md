# Documentación de Políticas OPA Gatekeeper

## Índice

1. [Introducción](#introducción)
2. [Requisitos Previos](#requisitos-previos)
3. [Instalación](#instalación)
4. [Políticas Implementadas](#políticas-implementadas)
   - [1. K8sRequiredResources](#1-k8srequiredresources)
   - [2. K8sTrustedRegistries](#2-k8strustedregistries)
   - [3. K8sRequiredLabels](#3-k8srequiredlabels)
   - [4. K8sPrivilegedContainers](#4-k8sprivilegedcontainers)
   - [5. K8sReadOnlyRootFS](#5-k8sreadonlyrootfs)
   - [6. K8sBlockHostPath](#6-k8sblockhostpath)
   - [7. K8sSecurityContext](#7-k8ssecuritycontext)
   - [8. K8sNetworkPolicyLabel](#8-k8snetworkpolicylabel)
   - [9. K8sRequiredProbes](#9-k8srequiredprobes)
   - [10. K8sRequirePDB](#10-k8srequirepdb)
5. [Aplicación de Políticas](#aplicación-de-políticas)
6. [Pruebas](#pruebas)
7. [Referencias](#referencias)

---

## Introducción

Este documento describe las políticas de seguridad y mejores prácticas implementadas en el cluster de Kubernetes utilizando **OPA Gatekeeper**. 

OPA Gatekeeper es un controlador de admisión que valida y aplica políticas en recursos de Kubernetes utilizando el lenguaje Rego de Open Policy Agent (OPA).

### Objetivos

- **Seguridad**: Prevenir configuraciones inseguras que puedan comprometer el cluster
- **Estandarización**: Asegurar que todos los recursos cumplan con estándares corporativos
- **Mejores Prácticas**: Fomentar el uso de configuraciones óptimas de Kubernetes
- **Cumplimiento**: Facilitar auditorías y cumplimiento normativo

---

## Requisitos Previos

- Cluster de Kubernetes 1.19+
- `kubectl` configurado con acceso administrativo
- OPA Gatekeeper 3.10+ instalado
- Helm 3+ (opcional, para instalación)

---

## Instalación

### Opción 1: Usando el script de instalación

```bash
./scripts/install/install_opa_gatekeeper.sh
```

### Opción 2: Manual con kubectl

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
```

### Opción 3: Usando Helm

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper/gatekeeper --name-template=gatekeeper --namespace gatekeeper-system --create-namespace
```

### Verificación de la instalación

```bash
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
```

---

## Políticas Implementadas

### 1. K8sRequiredResources

#### Descripción
Requiere que todos los contenedores definan límites de recursos (`requests` y `limits`) para CPU y memoria.

#### Objetivo
- Prevenir el agotamiento de recursos del cluster
- Mejorar la planificación de pods por el scheduler
- Facilitar el monitoreo y troubleshooting

#### Recursos Afectados
- `Pod`

#### Parámetros
- `enforceLimits`: (boolean) Requiere que se definan `limits`
- `enforceRequests`: (boolean) Requiere que se definan `requests`

#### Archivos
- **Template**: `manifests/politicas/1.1.k8srequiredresources-template.yaml`
- **Constraint**: `manifests/politicas/1.2.k8srequiredresources.yaml`

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-recursos
spec:
  containers:
  - name: nginx
    image: nginx:latest
    # ❌ FALTA: resources
```

**Mensaje de error:**
```
El contenedor 'nginx' no define resource limits
El contenedor 'nginx' no define resource requests
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-recursos
spec:
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

#### Exclusiones
- Namespace: `kube-system`, `gatekeeper-system`

---

### 2. K8sTrustedRegistries

#### Descripción
Solo permite el uso de imágenes de contenedores provenientes de registries confiables pre-aprobados.

#### Objetivo
- Prevenir el uso de imágenes maliciosas o no verificadas
- Control centralizado de fuentes de imágenes
- Reducir riesgos de supply chain attacks

#### Recursos Afectados
- `Pod`
- `Deployment`
- `StatefulSet`
- `DaemonSet`

#### Parámetros
- `registries`: (array) Lista de prefijos de registries permitidos

#### Archivos
- **Template**: `manifests/politicas/2.1.k8sallowedregistries-template.yaml`
- **Constraint**: `manifests/politicas/2.2.k8sallowedregistries.yaml`

#### Registries Permitidos por Defecto

```yaml
registries:
  - "docker.io/library/"
  - "gcr.io/"
  - "registry.k8s.io/"
  - "quay.io/"
  - "miregistro.empresa.com/"
```

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-registry-no-confiable
spec:
  containers:
  - name: app
    image: malicious.registry.com/app:latest  # ❌ Registry no permitido
```

**Mensaje de error:**
```
La imagen 'malicious.registry.com/app:latest' no proviene de un registry confiable. 
Registries permitidos: [docker.io/library/, gcr.io/, registry.k8s.io/, quay.io/]
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-registry-confiable
spec:
  containers:
  - name: nginx
    image: docker.io/library/nginx:latest  # ✅ Registry permitido
```

#### Personalización

Para agregar un registry privado, edita el archivo `2.2.k8sallowedregistries.yaml`:

```yaml
parameters:
  registries:
    - "docker.io/library/"
    - "tu-registry.empresa.com/"  # Agregar aquí
```

---

### 3. K8sRequiredLabels

#### Descripción
Requiere que los recursos tengan labels específicos con valores que cumplan patrones definidos mediante expresiones regulares.

#### Objetivo
- Facilitar la organización y búsqueda de recursos
- Permitir políticas de billing y chargeback
- Mejorar la trazabilidad y responsabilidad

#### Recursos Afectados
- `Pod`
- `Service`
- `Deployment`
- `StatefulSet`
- `DaemonSet`

#### Parámetros
- `labels`: Array de objetos con:
  - `key`: Nombre del label requerido
  - `allowedRegex`: (opcional) Patrón regex para validar el valor

#### Archivos
- **Template**: `manifests/politicas/3.1.k8srequiredlabels-template.yaml`
- **Constraint**: `manifests/politicas/3.2.k8srequiredlabels.yaml`

#### Labels Requeridos

| Label | Regex | Valores Permitidos | Obligatorio |
|-------|-------|-------------------|-------------|
| `app` | - | Cualquier valor | ✅ |
| `environment` | `^(dev\|staging\|production)$` | dev, staging, production | ✅ |
| `owner` | - | Cualquier valor | ✅ |
| `version` | `^v[0-9]+\\.[0-9]+\\.[0-9]+$` | v1.0.0, v2.1.3, etc. | ✅ |

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-labels
  labels:
    app: myapp
    # ❌ FALTAN: environment, owner, version
spec:
  containers:
  - name: nginx
    image: nginx:latest
```

**Mensaje de error:**
```
El recurso debe tener el label 'environment'
El recurso debe tener el label 'owner'
El recurso debe tener el label 'version'
```

#### Ejemplo con valor inválido

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-label-invalido
  labels:
    app: myapp
    environment: testing  # ❌ No cumple regex (solo dev|staging|production)
    owner: team-devops
    version: v1.0.0
```

**Mensaje de error:**
```
El valor del label 'environment' es 'testing', pero debe cumplir con el patrón: ^(dev|staging|production)$
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-labels
  labels:
    app: myapp
    environment: production
    owner: team-devops
    version: v1.2.3
spec:
  containers:
  - name: nginx
    image: nginx:latest
```

---

### 4. K8sPrivilegedContainers

#### Descripción
Bloquea la creación de contenedores en modo privilegiado.

#### Objetivo
- Prevenir escalación de privilegios
- Reducir la superficie de ataque
- Proteger el sistema host

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/4.1.k8sprivilegedcontainers-template.yaml`
- **Constraint**: `manifests/politicas/4.2.k8sprivilegedcontainers.yaml`

#### ¿Qué es un contenedor privilegiado?

Un contenedor privilegiado tiene acceso completo a todos los dispositivos del host y puede ejecutar operaciones que normalmente están restringidas. Esto incluye:
- Acceso a todos los dispositivos del host (`/dev/*`)
- Capacidad para montar filesystems
- Acceso a la red del host
- Capacidad para cargar módulos del kernel

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-privilegiado
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: true  # ❌ Modo privilegiado no permitido
```

**Mensaje de error:**
```
El contenedor 'nginx' está ejecutándose en modo privilegiado
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-no-privilegiado
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: false  # ✅ O simplemente omitir (false por defecto)
      runAsNonRoot: true
      allowPrivilegeEscalation: false
```

#### Casos de uso legítimos (excepciones)

Algunos pods del sistema pueden requerir modo privilegiado:
- Network plugins (Calico, Cilium)
- Storage drivers (CSI drivers)
- Monitoring agents (node-exporter)

**Solución**: Agregar estos namespaces a `excludedNamespaces` en el Constraint.

---

### 5. K8sReadOnlyRootFS

#### Descripción
Requiere que el filesystem raíz del contenedor sea de solo lectura.

#### Objetivo
- Prevenir modificación de binarios del contenedor
- Dificultar ataques de persistencia
- Fomentar el uso de arquitecturas inmutables

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/5.1.readOnlyRootFilesystem.yaml`
- **Constraint**: `manifests/politicas/5.2.k8sreadonlyrootfs.yaml`

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-readonly
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      runAsUser: 1000
      # ❌ FALTA: readOnlyRootFilesystem: true
```

**Mensaje de error:**
```
El contenedor 'nginx' no tiene el root filesystem en solo lectura
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-readonly
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      runAsUser: 1000
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: cache
      mountPath: /var/cache/nginx  # Para escritura temporal
    - name: run
      mountPath: /var/run
  volumes:
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
```

#### Consideraciones

Muchas aplicaciones necesitan escribir en ciertos directorios:
- Logs: `/var/log`
- Cache: `/var/cache`
- Runtime: `/var/run`, `/tmp`

**Solución**: Montar volúmenes `emptyDir` o `tmpfs` en esos directorios específicos.

---

### 6. K8sBlockHostPath

#### Descripción
Bloquea el uso de volúmenes `hostPath` que montan directorios del host en el contenedor.

#### Objetivo
- Prevenir acceso no autorizado al filesystem del host
- Evitar conflictos entre pods
- Mejorar la portabilidad de los pods

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/6.1.k8sblockhostpath-template.yaml`
- **Constraint**: `manifests/politicas/6.2.k8sblockhostpath.yaml`

#### ¿Por qué es peligroso hostPath?

Un volumen `hostPath` permite acceder al filesystem del nodo:
- Lectura de datos sensibles (`/etc/shadow`, certificados)
- Modificación de archivos críticos del sistema
- Escape del contenedor
- Persistencia de malware en el host

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-hostpath
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: host-volume
      mountPath: /data
  volumes:
  - name: host-volume
    hostPath:  # ❌ hostPath no permitido
      path: /tmp/data
```

**Mensaje de error:**
```
El Pod usa un volumen hostPath: host-volume
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-hostpath
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: cache-volume
      mountPath: /cache
  volumes:
  - name: cache-volume
    emptyDir: {}  # ✅ Alternativa segura
```

#### Alternativas a hostPath

| Necesidad | Solución Recomendada |
|-----------|---------------------|
| Almacenamiento temporal | `emptyDir` |
| Datos persistentes | `PersistentVolumeClaim` |
| Configuración | `ConfigMap` |
| Secretos | `Secret` |
| Información del nodo | Downward API |

---

### 7. K8sSecurityContext

#### Descripción
Requiere que todos los contenedores definan un `securityContext` y prohíbe ejecutar como usuario root (UID 0).

#### Objetivo
- Aplicar el principio de mínimo privilegio
- Prevenir escalación de privilegios
- Proteger contra vulnerabilidades de escape del contenedor

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/7.1.k8ssecuritycontext-template.yaml`
- **Constraint**: `manifests/politicas/7.2.k8ssecuritycontext.yaml`

#### Validaciones

1. El contenedor DEBE tener `securityContext` definido
2. El contenedor NO DEBE ejecutarse como root (`runAsUser != 0`)

#### Ejemplo de violación (sin securityContext)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-securitycontext
spec:
  containers:
  - name: nginx
    image: nginx:latest
    # ❌ FALTA: securityContext
```

**Mensaje de error:**
```
El contenedor 'nginx' no tiene securityContext definido
```

#### Ejemplo de violación (ejecutando como root)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-como-root
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      runAsUser: 0  # ❌ Root no permitido
```

**Mensaje de error:**
```
El contenedor 'nginx' se ejecuta como root
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-seguro
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      runAsUser: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
```

#### Mejores prácticas de securityContext

```yaml
securityContext:
  # Usuario no privilegiado
  runAsUser: 1000
  runAsGroup: 3000
  runAsNonRoot: true
  
  # Filesystem
  readOnlyRootFilesystem: true
  
  # Privilegios
  allowPrivilegeEscalation: false
  privileged: false
  
  # Capabilities
  capabilities:
    drop:
    - ALL
    add:
    - NET_BIND_SERVICE  # Solo si necesitas ports < 1024
```

---

### 8. K8sNetworkPolicyLabel

#### Descripción
Requiere que los pods tengan el label `network-policy: enabled` para confirmar que están protegidos por NetworkPolicies.

#### Objetivo
- Asegurar que todos los pods tengan políticas de red aplicadas
- Documentar explícitamente la protección de red
- Facilitar auditorías de segmentación de red

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/8.1.k8srequirednetworkpolicy-template.yaml`
- **Constraint**: `manifests/politicas/8.2.k8srequirednetworkpolicy.yaml`

#### Parámetros
- `requiredLabel`: Label requerido (default: `network-policy`)
- `requiredValue`: Valor esperado (default: `enabled`)

#### Ejemplo de violación

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-label-netpol
  labels:
    app: myapp
    # ❌ FALTA: network-policy: enabled
spec:
  containers:
  - name: nginx
    image: nginx:latest
```

**Mensaje de error:**
```
El Pod 'pod-sin-label-netpol' debe tener el label 'network-policy' para confirmar que está protegido por NetworkPolicy
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-netpol
  labels:
    app: myapp
    network-policy: enabled  # ✅ Label requerido
spec:
  containers:
  - name: nginx
    image: nginx:latest
```

#### NetworkPolicy de ejemplo

Antes de desplegar pods, crear NetworkPolicies en el namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: default
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
```

#### Enfoque Alternativo

En lugar de validar por label, se puede configurar para validar que el namespace tenga NetworkPolicies definidas. Ver documentación de `K8sPodRequiresNetworkPolicy` en el código fuente.

---

### 9. K8sRequiredProbes

#### Descripción
Requiere que todos los contenedores definan `livenessProbe` y `readinessProbe`.

#### Objetivo
- Mejorar la disponibilidad de aplicaciones
- Facilitar la detección automática de fallos
- Prevenir el tráfico a pods no listos

#### Recursos Afectados
- `Pod`

#### Archivos
- **Template**: `manifests/politicas/9.1.k8srequiredprobes-template.yaml`
- **Constraint**: `manifests/politicas/9.2.k8srequiredprobes.yaml`

#### Diferencia entre Probes

| Probe | Propósito | Acción en fallo |
|-------|-----------|----------------|
| **livenessProbe** | Determina si el contenedor está vivo | Reinicia el contenedor |
| **readinessProbe** | Determina si el contenedor puede recibir tráfico | Quita del Service endpoints |
| **startupProbe** | Para aplicaciones con inicio lento | Desactiva liveness hasta que pase |

#### Ejemplo de violación (sin probes)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-sin-probes
spec:
  containers:
  - name: nginx
    image: nginx:latest
    # ❌ FALTAN: livenessProbe y readinessProbe
```

**Mensaje de error:**
```
El contenedor 'nginx' no tiene livenessProbe
El contenedor 'nginx' no tiene readinessProbe
```

#### Ejemplo de violación (falta readiness)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-solo-liveness
spec:
  containers:
  - name: nginx
    image: nginx:latest
    livenessProbe:
      httpGet:
        path: /health
        port: 80
    # ❌ FALTA: readinessProbe
```

**Mensaje de error:**
```
El contenedor 'nginx' no tiene readinessProbe
```

#### Ejemplo correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-con-probes
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    
    livenessProbe:
      httpGet:
        path: /healthz
        port: 80
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    readinessProbe:
      httpGet:
        path: /ready
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

#### Tipos de Probes

##### HTTP GET
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: Custom-Header
      value: Awesome
```

##### TCP Socket
```yaml
livenessProbe:
  tcpSocket:
    port: 3306
```

##### Exec Command
```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
```

#### Configuración Recomendada

```yaml
# Para aplicaciones web típicas
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30   # Tiempo para iniciar
  periodSeconds: 10         # Cada cuánto verificar
  timeoutSeconds: 5         # Timeout del probe
  failureThreshold: 3       # Fallos antes de reiniciar

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5    # Más corto que liveness
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

---

### 10. K8sRequirePDB

#### Descripción
Requiere que los namespaces de producción tengan un `PodDisruptionBudget` configurado antes de permitir Deployments.

#### Objetivo
- Garantizar alta disponibilidad durante mantenimientos
- Prevenir interrupciones masivas de servicio
- Proteger aplicaciones críticas

#### Recursos Afectados
- `Deployment`
- `StatefulSet`
- `DaemonSet`

#### Archivos
- **Template**: `manifests/politicas/10.1.k8srequirepdb-template.yaml`
- **Constraint**: `manifests/politicas/10.2.k8srequirepdb.yaml`

#### Requisito Especial

Esta política requiere que Gatekeeper tenga **data sync** habilitado para consultar recursos existentes.

#### Configurar Data Sync

```bash
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
```

#### ¿Qué es un PodDisruptionBudget?

Un PDB limita el número de pods que pueden estar no disponibles simultáneamente durante:
- Actualizaciones de nodos
- Drenaje de nodos
- Escalado del cluster
- Mantenimiento programado

#### Ejemplo de violación

```yaml
# Namespace production sin PDB
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-sin-pdb
  namespace: production  # ❌ Namespace "prod*" sin PDB
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

**Mensaje de error:**
```
El namespace 'production' no tiene PodDisruptionBudget configurado
```

#### Ejemplo correcto

Primero crear el PDB:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: production
spec:
  minAvailable: 1  # Al menos 1 pod siempre disponible
  selector:
    matchLabels:
      app: myapp
```

Luego crear el Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-con-pdb
  namespace: production  # ✅ Namespace tiene PDB
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

#### Configuración de PDB

##### Opción 1: minAvailable
```yaml
spec:
  minAvailable: 2  # Mínimo 2 pods disponibles
  selector:
    matchLabels:
      app: myapp
```

##### Opción 2: maxUnavailable
```yaml
spec:
  maxUnavailable: 1  # Máximo 1 pod no disponible
  selector:
    matchLabels:
      app: myapp
```

##### Opción 3: Porcentajes
```yaml
spec:
  minAvailable: 80%  # 80% de pods disponibles
  selector:
    matchLabels:
      app: myapp
```

#### Recomendaciones

| Replicas | minAvailable | maxUnavailable | Razón |
|----------|-------------|----------------|-------|
| 1 | 0 | 1 | Pod único puede ser interrumpido |
| 2 | 1 | 1 | Mantener 1 activo siempre |
| 3+ | 2 | 1 | Alta disponibilidad |
| 5+ | 80% | 20% | Usar porcentajes |

---

## Aplicación de Políticas

### Aplicar todas las políticas

```bash
# Aplicar Templates
./scripts/apply_templates.sh

# Aplicar Constraints
./scripts/apply_constraints.sh
```

### Aplicar una política específica

```bash
# Ejemplo: Política 1 (K8sRequiredResources)
kubectl apply -f manifests/politicas/1.1.k8srequiredresources-template.yaml
kubectl apply -f manifests/politicas/1.2.k8srequiredresources.yaml
```

### Verificar políticas aplicadas

```bash
# Ver ConstraintTemplates
kubectl get constrainttemplates

# Ver Constraints
kubectl get constraints

# Ver detalles de una constraint
kubectl describe constraint require-pod-resources
```

### Modos de aplicación

#### Modo Audit (dryrun)
Las violaciones se registran pero no se bloquean:

```yaml
spec:
  enforcementAction: dryrun
```

#### Modo Warn
Las violaciones generan advertencias pero no se bloquean:

```yaml
spec:
  enforcementAction: warn
```

#### Modo Deny (defecto)
Las violaciones se bloquean:

```yaml
spec:
  enforcementAction: deny
```

---

## Pruebas

### Estructura de Tests

```
tests/
├── common.sh              # Funciones comunes
├── test_policy_1.sh       # Test K8sRequiredResources
├── test_policy_2.sh       # Test K8sTrustedRegistries
├── test_policy_3.sh       # Test K8sRequiredLabels
├── test_policy_4.sh       # Test K8sPrivilegedContainers
├── test_policy_5.sh       # Test K8sReadOnlyRootFS
├── test_policy_6.sh       # Test K8sBlockHostPath
├── test_policy_7.sh       # Test K8sSecurityContext
├── test_policy_8.sh       # Test K8sNetworkPolicyLabel
├── test_policy_9.sh       # Test K8sRequiredProbes
├── test_policy_10.sh      # Test K8sRequirePDB
└── run_all_tests.sh       # Ejecuta todos los tests
```

### Ejecutar tests

```bash
# Setup inicial
./tests/setup_test_environment.sh

# Ejecutar test individual
./tests/test_policy_1.sh

# Ejecutar todos los tests
./tests/run_all_tests.sh

# Limpieza
./tests/cleanup.sh
```

### Flujo de cada test

Cada test sigue este flujo demostrativo:

1. **Sin Política**: Crea recurso inseguro → Verifica que se crea → Muestra el pod funcionando
2. **Aplicar Política**: Instala ConstraintTemplate + Constraint
3. **Violación**: Intenta recurso inseguro → Verifica que es bloqueado → Muestra mensaje de error
4. **Cumplimiento**: Crea recurso seguro → Verifica que se crea → Muestra el pod funcionando
5. **Limpieza**: Elimina recursos y políticas

### Ejemplo de salida

```bash
========================================
  TEST POLÍTICA 1: K8sRequiredResources
========================================

▶ PASO 1: Probando SIN la política aplicada
ℹ Aplicando Pod sin recursos definidos...
✓ Pod creado exitosamente (no hay política que lo bloquee)
ℹ Esperando 5 segundos para que el Pod se cree...
NAME               READY   STATUS    RESTARTS   AGE
test-no-resources  1/1     Running   0          5s
✓ Sin política, el Pod se crea aunque no tenga recursos definidos

▶ PASO 2: Aplicando la política
constrainttemplate.templates.gatekeeper.sh/k8srequiredresources created
k8srequiredresources.constraints.gatekeeper.sh/require-pod-resources created
✓ Constraint 'require-pod-resources' está activa

▶ PASO 3: Intentando crear Pod SIN recursos (debe fallar)
✓ Pod bloqueado correctamente por la política
Mensaje de Gatekeeper:
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: 
[require-pod-resources] El contenedor 'nginx' no define resource limits
[require-pod-resources] El contenedor 'nginx' no define resource requests

▶ PASO 4: Creando Pod CON recursos definidos (debe pasar)
✓ Pod creado exitosamente con recursos definidos

▶ PASO 5: Verificando el Pod
ℹ Esperando 5 segundos para que el Pod se cree...
NAME                  READY   STATUS    RESTARTS   AGE
test-with-resources   1/1     Running   0          5s

▶ Limpieza
pod "test-with-resources" deleted
constraint.constraints.gatekeeper.sh "require-pod-resources" deleted
constrainttemplate.templates.gatekeeper.sh "k8srequiredresources" deleted
✓ Test completado!
```

---

## Eliminación de Políticas

### Eliminar todas las políticas

```bash
# Eliminar Constraints
./scripts/delete_constraints.sh

# Eliminar ConstraintTemplates
./scripts/delete_templates.sh
```

### Eliminar una política específica

```bash
# Ejemplo: Política 1
kubectl delete -f manifests/politicas/1.2.k8srequiredresources.yaml
kubectl delete -f manifests/politicas/1.1.k8srequiredresources-template.yaml
```

### Desinstalar Gatekeeper completamente

```bash
# Eliminar todas las políticas primero
./scripts/delete_constraints.sh
./scripts/delete_templates.sh

# Desinstalar Gatekeeper
kubectl delete -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

# Verificar limpieza
kubectl get crd | grep gatekeeper
kubectl get ns gatekeeper-system
```

---

## Mejores Prácticas

### 1. Implementación Gradual

- ✅ Comenzar con modo `dryrun` o `warn`
- ✅ Monitorear violaciones durante al menos 2 semanas
- ✅ Comunicar cambios a los equipos con anticipación
- ✅ Documentar excepciones legítimas

### 2. Excepciones

Usar `excludedNamespaces` para casos especiales:

```yaml
spec:
  match:
    excludedNamespaces:
      - "kube-system"
      - "istio-system"
      - "monitoring"
```

O usar `namespaceSelector` para aplicar solo a ciertos namespaces:

```yaml
spec:
  match:
    namespaceSelector:
      matchLabels:
        enforce-policies: "true"
```

### 3. Versionado de Políticas

Mantener las políticas en Git con versionado:

```bash
git/
├── policies/
│   ├── v1.0/
│   │   ├── k8srequiredresources/
│   │   └── ...
│   └── v1.1/
│       ├── k8srequiredresources/
│       └── ...
└── CHANGELOG.md
```

### 4. Testing Continuo

- ✅ Ejecutar tests en CI/CD antes de aplicar cambios
- ✅ Validar políticas en clusters de staging primero
- ✅ Mantener tests actualizados con las políticas

### 5. Documentación

- ✅ Documentar el propósito de cada política
- ✅ Incluir ejemplos de conformidad y violación
- ✅ Mantener un runbook de troubleshooting
- ✅ Comunicar cambios mediante release notes

### 7. Excepciones Temporales

Para casos de emergencia, usar annotations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emergency-pod
  annotations:
    admission.gatekeeper.sh/ignore: "true"  # ⚠️ Solo para emergencias
```

**Nota**: Esta annotation debe ser controlada mediante RBAC.

---

## Casos de Uso Avanzados

### Política por Entorno

Aplicar políticas más estrictas en producción:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: production-labels
spec:
  match:
    namespaceSelector:
      matchLabels:
        environment: production
  parameters:
    labels:
      - key: "sla"
      - key: "cost-center"
      - key: "compliance-level"
```

### Políticas por Equipo

Diferentes políticas para diferentes equipos:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sTrustedRegistries
metadata:
  name: team-a-registries
spec:
  match:
    namespaceSelector:
      matchLabels:
        team: "team-a"
  parameters:
    registries:
      - "team-a-registry.company.com/"
```

### Dry-run para Nuevas Políticas

Probar impacto antes de aplicar:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNewPolicy
metadata:
  name: test-new-policy
spec:
  enforcementAction: dryrun  # Solo auditoría
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

### Políticas Temporales

Aplicar políticas solo durante ciertos períodos:

```rego
package k8stemporalpolicy

violation[{"msg": msg}] {
  # Solo aplicar durante días laborables
  now := time.now_ns()
  weekday := time.weekday(now)
  weekday >= 1  # Lunes
  weekday <= 5  # Viernes
  
  # ... resto de la validación ...
}
```

---

## Referencias

### Documentación Oficial

- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [OPA (Open Policy Agent)](https://www.openpolicyagent.org/)
- [Rego Language](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Kubernetes Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)

### Recursos Adicionales

- [Gatekeeper Policy Library](https://github.com/open-policy-agent/gatekeeper-library)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://www.nsa.gov/Press-Room/News-Highlights/Article/Article/2716980/)

### Comunidad

- [Gatekeeper GitHub](https://github.com/open-policy-agent/gatekeeper)
- [OPA Slack](https://openpolicyagent.slack.com/)
- [CNCF Slack - #gatekeeper](https://cloud-native.slack.com/)

### Herramientas Relacionadas

- **Conftest**: Testing de configuraciones con OPA
- **Konstraint**: Generador de políticas Gatekeeper
- **Gatekeeper Policy Manager**: UI web para Gatekeeper
- **Kyverno**: Alternativa a Gatekeeper (políticas en YAML)

---

## Apéndices

### A. Resumen de Comandos

```bash
# Instalación
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

# Aplicar políticas
kubectl apply -f manifests/politicas/

# Ver constraints
kubectl get constraints

# Ver templates
kubectl get constrainttemplates

# Ver violaciones
kubectl get constraint <nombre> -o jsonpath='{.status.violations}'

# Cambiar enforcement mode
kubectl patch constraint <nombre> --type=merge -p '{"spec":{"enforcementAction":"dryrun"}}'

# Logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager

# Desinstalar
kubectl delete -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
```

### B. Checklist de Implementación

- [ ] Cluster de Kubernetes funcionando
- [ ] kubectl configurado con acceso admin
- [ ] Gatekeeper instalado y funcionando
- [ ] Data sync configurado (para política 10)
- [ ] Namespaces de exclusión definidos
- [ ] Políticas aplicadas en modo dryrun
- [ ] Equipos notificados sobre cambios
- [ ] Período de observación completado (2 semanas)
- [ ] Políticas aplicadas en modo warn
- [ ] Período de advertencias completado (2 semanas)
- [ ] Políticas aplicadas en modo deny
- [ ] Tests automatizados ejecutados
- [ ] Documentación actualizada
- [ ] Runbook de troubleshooting disponible

### C. Glosario

| Término | Definición |
|---------|-----------|
| **OPA** | Open Policy Agent - Motor de políticas de propósito general |
| **Gatekeeper** | Implementación de OPA como admission controller de Kubernetes |
| **Rego** | Lenguaje de consulta para definir políticas en OPA |
| **ConstraintTemplate** | Define la lógica de una política (código Rego) |
| **Constraint** | Instancia de un ConstraintTemplate con parámetros específicos |
| **Admission Controller** | Componente que intercepta requests al API server |
| **ValidatingWebhook** | Webhook que valida recursos antes de crearlos |
| **Enforcement Action** | Modo de aplicación: deny, dryrun, o warn |
| **Data Sync** | Sincronización de recursos del cluster para consultas |

### D. Tabla de Compatibilidad

| Gatekeeper | Kubernetes | OPA |
|------------|-----------|-----|
| 3.14.x | 1.24 - 1.28 | 0.57.x |
| 3.13.x | 1.23 - 1.27 | 0.55.x |
| 3.12.x | 1.22 - 1.26 | 0.50.x |
| 3.11.x | 1.21 - 1.25 | 0.48.x |

---

