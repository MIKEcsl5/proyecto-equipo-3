#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 8: K8sNetworkPolicyLabel"
print_info "Esta política requiere el label 'network-policy: enabled'"

print_step "PASO 1: Creando NetworkPolicies en namespace default"
kubectl apply -f - <<NETPOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
NETPOL

print_step "PASO 2: Probando SIN la política de label"
kubectl apply -f manifests/deployments/deployment8_falla.yaml
check_result "Pod sin label network-policy creado" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-no-netpol-label -o wide --show-labels
kubectl delete -f manifests/deployments/deployment8_falla.yaml --ignore-not-found=true

print_step "PASO 3: Aplicando la política de label"
kubectl apply -f manifests/politicas/8.1.k8srequirednetworkpolicy-template.yaml
kubectl apply -f manifests/politicas/8.2.k8srequirednetworkpolicy.yaml
wait_for_constraint "require-netpol-label"

print_step "PASO 4: Intentando Pod SIN label network-policy (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment8_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - falta label network-policy"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment8_falla.yaml --ignore-not-found=true
fi

print_step "PASO 5: Creando Pod CON label network-policy: enabled (debe pasar)"
kubectl apply -f manifests/deployments/deployment8_pasa.yaml
check_result "✓ Pod con label correcto creado" "✗ ERROR"

print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-with-netpol-label -o wide --show-labels

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment8_pasa.yaml --ignore-not-found=true
kubectl delete networkpolicy default-deny-ingress allow-same-namespace -n default --ignore-not-found=true
kubectl delete -f manifests/politicas/8.2.k8srequirednetworkpolicy.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/8.1.k8srequirednetworkpolicy-template.yaml --ignore-not-found=true
print_success "Test completado!"
