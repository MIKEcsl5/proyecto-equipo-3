# OPA Gatekeeper: Policy as Code para Kubernetes

## 📋 Descripción del Proyecto

Este proyecto implementa **OPA (Open Policy Agent) Gatekeeper** como solución de Policy as Code para la gobernanza y seguridad de clústeres Kubernetes. Gatekeeper permite definir, validar y aplicar políticas de seguridad de manera declarativa y automatizada, garantizando que todos los recursos desplegados en el clúster cumplan con los estándares de seguridad y mejores prácticas de la organización.

### ¿Por qué es importante?

En entornos de producción, asegurar que cada deployment, pod y servicio cumple con políticas de seguridad es crítico. Sin un sistema de políticas automatizado, las organizaciones dependen de revisiones manuales propensas a errores humanos. Gatekeeper resuelve este problema al:

- **Prevenir configuraciones inseguras antes del despliegue**: Valida recursos en tiempo real mediante admission webhooks
- **Estandarizar prácticas de seguridad**: Garantiza consistencia en todos los namespaces y equipos
- **Auditar cumplimiento**: Permite verificar que los recursos existentes cumplen con las políticas establecidas
- **Reducir superficie de ataque**: Bloquea containers privilegiados, imágenes no confiables y configuraciones peligrosas

Este proyecto implementa 10 políticas críticas de seguridad que cubren desde límites de recursos hasta validación de NetworkPolicies, creando múltiples capas de defensa para el clúster.

## 🏗️ Arquitectura

### Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes API Server                        │
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │ Authentication│───▶│Authorization │───▶│ Admission       │  │
│  └──────────────┘    └──────────────┘    │ Controllers     │  │
│                                            └────────┬────────┘  │
└─────────────────────────────────────────────────────┼───────────┘
                                                       │
                                                       ▼
                                    ┌──────────────────────────────┐
                                    │ ValidatingAdmissionWebhook   │
                                    │                              │
                                    │   ┌──────────────────────┐  │
                                    │   │  OPA Gatekeeper      │  │
                                    │   │                      │  │
                                    │   │  ┌───────────────┐  │  │
                                    │   │  │ OPA Engine    │  │  │
                                    │   │  │ (Rego Policy) │  │  │
                                    │   │  └───────────────┘  │  │
                                    │   │                      │  │
                                    │   │  ┌───────────────┐  │  │
                                    │   │  │ Controller    │  │  │
                                    │   │  │ (Reconciler)  │  │  │
                                    │   │  └───────────────┘  │  │
                                    │   └──────────────────────┘  │
                                    └──────────┬───────────────────┘
                                               │
                              ┌────────────────┴────────────────┐
                              │                                  │
                              ▼                                  ▼
                    ┌──────────────────┐            ┌──────────────────┐
                    │ ConstraintTemplate│            │   Constraint     │
                    │                   │            │                  │
                    │ Define políticas  │───────────▶│ Instancias de    │
                    │ genéricas en Rego │            │ políticas        │
                    │                   │            │ específicas      │
                    └──────────────────┘            └──────────────────┘
```

### ¿Cómo Funciona Gatekeeper?

Gatekeeper opera como un **ValidatingAdmissionWebhook** que intercepta todas las solicitudes al API Server de Kubernetes. Cuando un recurso (pod, deployment, service, etc.) intenta ser creado o modificado:

1. **Interceptación**: El API Server envía la solicitud al webhook de Gatekeeper
2. **Evaluación**: El motor OPA evalúa el recurso contra las políticas definidas en Rego
3. **Decisión**: Gatekeeper acepta o rechaza la solicitud según el cumplimiento
4. **Respuesta**: El API Server procede o bloquea basándose en la respuesta

#### Componentes Principales

**ConstraintTemplate (CRD):**
- Define políticas genéricas usando el lenguaje Rego
- Especifica el esquema de parámetros configurables
- Actúa como plantilla reutilizable para múltiples constraints

**Constraint (CRD):**
- Instancia específica de un ConstraintTemplate
- Define los parámetros concretos (namespaces, valores, excepciones)
- Establece el modo de aplicación (deny, dryrun, warn)

**Reconciliation Loop:**
- Controller que continuamente verifica el estado actual vs deseado
- Audita recursos existentes para detectar violaciones
- Mantiene sincronizados los constraints con el estado del clúster

## 📦 Prerrequisitos

### Infraestructura Base

El laboratorio requiere **3 máquinas virtuales Rocky Linux 9** con las siguientes especificaciones:

| Componente | Cantidad | Especificaciones |
|------------|----------|------------------|
| **Master Node** | 1 | 3 GB RAM, 2 vCPU |
| **Worker Nodes** | 2 | 3 GB RAM, 2 vCPU (cada uno) |

**Configuración de Red (cada VM):**
- **Interfaz NAT**: Acceso a Internet
- **Interfaz Host-Only**: Comunicación entre nodos (IPs fijas)

### Software Requerido

| Software | Versión Mínima | Propósito |
|----------|----------------|-----------|
| Rocky Linux | 9.x | Sistema operativo base |
| Kubernetes | 1.30+ | Orquestación de containers |
| Container Runtime | containerd/CRI-O | Ejecución de containers |
| Helm | 3.x | Gestor de paquetes K8s |
| kubectl | 1.30+ | CLI de Kubernetes |

### Configuración Kubernetes Base

Antes de instalar Gatekeeper, el clúster debe tener:

- ✅ IPs fijas configuradas en todas las interfaces Host-Only
- ✅ Hostnames únicos y resolución DNS local
- ✅ SELinux en modo permissive o disabled
- ✅ Firewall configurado (puertos 6443, 2379-2380, 10250-10252, 30000-32767)
- ✅ Swap deshabilitado en todos los nodos
- ✅ Módulos kernel cargados: `br_netfilter`, `overlay`
- ✅ **ValidatingAdmissionPolicy** habilitado en kube-apiserver

## 🚀 Instalación Paso a Paso

### Paso 1: Instalación del Clúster Kubernetes

Sigue la guía oficial para Rocky Linux:

```bash
# En todos los nodos (master y workers)
# 1. Deshabilitar swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. Cargar módulos kernel
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Configurar parámetros sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 4. Instalar containerd
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd

# 5. Agregar repositorio de Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF

# 6. Instalar componentes Kubernetes
sudo dnf install -y kubelet kubeadm kubectl
sudo systemctl enable kubelet

# 7. Configurar firewall (master)
sudo firewall-cmd --permanent --add-port={6443,2379-2380,10250,10251,10252}/tcp
sudo firewall-cmd --reload

# 7. Configurar firewall (workers)
sudo firewall-cmd --permanent --add-port={10250,30000-32767}/tcp
sudo firewall-cmd --reload
```

**Solo en el nodo Master:**

```bash
# Inicializar el clúster (ajusta --pod-network-cidr según tu CNI)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint=<MASTER_IP>:6443

# Configurar kubectl para usuario regular
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Instalar CNI plugin (ejemplo: Calico)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml
```

**En los nodos Workers:**

```bash
# Ejecutar el comando join proporcionado por kubeadm init
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

**Guía completa de referencia:**  
https://www.linuxtechi.com/install-kubernetes-on-rockylinux-almalinux/

### Paso 2: Instalar Helm

```bash
# Descargar e instalar Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar instalación
helm version
```

### Paso 3: Instalar OPA Gatekeeper

```bash
# Agregar el repositorio de Gatekeeper
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

# Instalar Gatekeeper en el namespace gatekeeper-system
helm install gatekeeper/gatekeeper \
  --name-template=gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set enableExternalData=false \
  --set validatingWebhookTimeoutSeconds=5 \
  --set mutatingWebhookTimeoutSeconds=3

# Verificar instalación
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
```

**Salida esperada:**

```
NAME                                             READY   STATUS    RESTARTS   AGE
gatekeeper-audit-7d9c8d8f4d-xxxxx               1/1     Running   0          2m
gatekeeper-controller-manager-5c8f9b7d9-xxxxx   1/1     Running   0          2m
gatekeeper-controller-manager-5c8f9b7d9-yyyyy   1/1     Running   0          2m
gatekeeper-controller-manager-5c8f9b7d9-zzzzz   1/1     Running   0          2m
```

## ⚙️ Configuración de Políticas

### Estructura de Políticas

Todas las políticas siguen el patrón de dos recursos:

1. **ConstraintTemplate**: Define la lógica en Rego
2. **Constraint**: Aplica la política a namespaces específicos

### Ejemplo: Requerir Resource Limits

**ConstraintTemplate:**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredresources
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredResources
      validation:
        openAPIV3Schema:
          type: object
          properties:
            limits:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredresources

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits
          msg := sprintf("Container '%v' no tiene resource limits definidos", [container.name])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.requests
          msg := sprintf("Container '%v' no tiene resource requests definidos", [container.name])
        }
```

**Constraint:**

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: require-resources
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: ["production", "staging"]
  parameters:
    limits: ["cpu", "memory"]
```

### Aplicar Políticas

```bash
# Crear el ConstraintTemplate
kubectl apply -f constraint-template.yaml

# Esperar a que el CRD esté disponible
kubectl wait --for condition=established --timeout=60s crd/k8srequiredresources.constraints.gatekeeper.sh

# Aplicar el Constraint
kubectl apply -f constraint.yaml

# Verificar política activa
kubectl get constraints
```

## 🛡️ Políticas de Seguridad Implementadas

### 1. Requerir Resource Limits

**Propósito**: Prevenir que pods consuman recursos ilimitados del clúster.

**Qué valida**:
- Todos los containers deben definir `resources.limits.cpu` y `resources.limits.memory`
- Todos los containers deben definir `resources.requests.cpu` y `resources.requests.memory`

**Por qué es importante**: Sin límites, un container puede consumir todos los recursos del nodo, causando degradación o caída de otros servicios (noisy neighbor problem).

---

### 2. Bloquear Imágenes de Registries No Confiables

**Propósito**: Permitir solo imágenes de repositorios autorizados.

**Qué valida**:
- Las imágenes deben provenir de registries en la lista blanca (ej: `gcr.io`, `docker.io/library`, registry privado)
- Rechaza imágenes con tag `latest` (fomenta versionado explícito)

**Por qué es importante**: Previene la ejecución de imágenes maliciosas o no auditadas que podrían comprometer el clúster.

---

### 3. Requerir Labels Específicos

**Propósito**: Garantizar metadata consistente para gestión y facturación.

**Qué valida**:
- Pods deben tener labels obligatorios: `app`, `environment`, `owner`, `cost-center`
- Los valores deben cumplir patrones específicos (ej: environment solo puede ser `dev`, `staging`, `prod`)

**Por qué es importante**: Permite rastreo de costos, identificación de responsables y aplicación correcta de NetworkPolicies.

---

### 4. Prohibir Privileged Containers

**Propósito**: Bloquear containers con acceso root al host.

**Qué valida**:
- `securityContext.privileged` debe ser `false` o no estar presente
- Aplica a todos los containers e initContainers

**Por qué es importante**: Containers privilegiados pueden escapar del aislamiento y comprometer el nodo host completo.

---

### 5. Forzar readOnlyRootFilesystem

**Propósito**: Hacer el filesystem del container inmutable.

**Qué valida**:
- `securityContext.readOnlyRootFilesystem` debe ser `true`
- Excepciones permitidas para containers que requieren escritura (con justificación)

**Por qué es importante**: Previene que malware modifique binarios del container o descargue herramientas adicionales.

---

### 6. Bloquear hostPath Volumes

**Propósito**: Prevenir acceso directo al filesystem del host.

**Qué valida**:
- Ningún pod puede usar volúmenes de tipo `hostPath`
- Excepción: DaemonSets del sistema con label especial

**Por qué es importante**: hostPath permite leer/escribir archivos críticos del host como `/etc/shadow`, certificados TLS, o sockets de Docker/containerd.

---

### 7. Validar SecurityContext

**Propósito**: Aplicar configuraciones de seguridad mínimas.

**Qué valida**:
- `runAsNonRoot: true` (no ejecutar como UID 0)
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ["ALL"]` (eliminar todas las capabilities)
- `seccompProfile.type: RuntimeDefault`

**Por qué es importante**: Implementa defensa en profundidad siguiendo el principio de mínimo privilegio.

---

### 8. Requerir NetworkPolicies

**Propósito**: Garantizar aislamiento de red a nivel de namespace.

**Qué valida**:
- Todo namespace (excepto `kube-system`) debe tener al menos una NetworkPolicy
- La política debe ser de tipo Ingress o Egress (no puede ser vacía)
- Coordinación con Equipo 4 para políticas específicas

**Por qué es importante**: Por defecto, Kubernetes permite todo el tráfico entre pods. NetworkPolicies implementan microsegmentación.

---

### 9. Validar Probes (Liveness/Readiness)

**Propósito**: Asegurar que las aplicaciones sean monitoreables y resilientes.

**Qué valida**:
- Todos los pods en producción deben tener `livenessProbe`
- Todos los pods en producción deben tener `readinessProbe`
- Las probes deben tener timeouts y períodos configurados

**Por qué es importante**: Sin probes, Kubernetes no puede detectar aplicaciones colgadas o reiniciar containers no saludables.

---

### 10. Requerir PodDisruptionBudgets para Producción

**Propósito**: Garantizar alta disponibilidad durante actualizaciones.

**Qué valida**:
- Deployments con `replicas > 1` en namespace `production` deben tener un PDB asociado
- El PDB debe permitir al menos 1 réplica disponible (`minAvailable: 1`)

**Por qué es importante**: PDBs previenen que operaciones de mantenimiento (node drains, upgrades) causen indisponibilidad total de aplicaciones críticas.

## ✅ Comandos de Validación

### Verificar Estado de Gatekeeper

```bash
# Ver pods de Gatekeeper
kubectl get pods -n gatekeeper-system

# Ver logs del controller
kubectl logs -n gatekeeper-system -l control-plane=controller-manager -f

# Ver logs del auditor
kubectl logs -n gatekeeper-system -l control-plane=audit-controller
```

### Verificar Políticas Instaladas

```bash
# Listar todos los ConstraintTemplates
kubectl get constrainttemplates

# Listar todos los Constraints
kubectl get constraints --all-namespaces

# Ver detalles de un constraint específico
kubectl describe k8srequiredresources require-resources
```

### Probar Políticas

```bash
# Intentar crear un pod sin resource limits (debe fallar)
kubectl run test-pod --image=nginx --namespace=production

# Salida esperada:
# Error from server ([require-resources] Container 'test-pod' no tiene resource limits definidos): admission webhook "validation.gatekeeper.sh" denied the request

# Crear un pod que cumple la política (debe funcionar)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  namespace: production
  labels:
    app: test
    environment: prod
    owner: devops-team
    cost-center: engineering
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: nginx
    image: gcr.io/google-samples/hello-app:1.0
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    livenessProbe:
      httpGet:
        path: /
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
EOF
```

### Auditar Recursos Existentes

```bash
# Ver violaciones detectadas por el auditor
kubectl get constraints -o json | jq '.items[] | select(.status.totalViolations > 0) | {name: .metadata.name, violations: .status.totalViolations}'

# Ver detalles de violaciones de un constraint
kubectl get k8srequiredresources require-resources -o jsonpath='{.status.violations}' | jq .

# Generar reporte de cumplimiento
kubectl get constraints --all-namespaces -o wide
```

### Modo Dry-Run (Testing)

```bash
# Cambiar un constraint a modo dryrun (no bloquea, solo reporta)
kubectl patch k8srequiredresources require-resources --type='json' -p='[{"op": "replace", "path": "/spec/enforcementAction", "value":"dryrun"}]'

# Ver warnings en los logs de audit
kubectl logs -n gatekeeper-system -l control-plane=audit-controller | grep violation
```

### Métricas de Gatekeeper

```bash
# Ver métricas de Prometheus (si está habilitado)
kubectl port-forward -n gatekeeper-system svc/gatekeeper-controller-manager-metrics-service 8888:8888

# Acceder a: http://localhost:8888/metrics
# Métricas útiles:
# - gatekeeper_constraints: Número de constraints activos
# - gatekeeper_constraint_templates: Número de templates
# - gatekeeper_violations: Violaciones detectadas
```


## 📚 Referencias

- [Documentación Oficial de Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [OPA Rego Language](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library)
- [Instalación K8s en Rocky Linux](https://www.linuxtechi.com/install-kubernetes-on-rockylinux-almalinux/)
- [Kubernetes Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)

## 📄 Licencia

Este proyecto es parte de un ejercicio académico de seguridad en Kubernetes.

---

---

**Autor**: [Equipo 3]  
**Fecha**:06 Noviembre 2025   
**Versión**: 1.0

