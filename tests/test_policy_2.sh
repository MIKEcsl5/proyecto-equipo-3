#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 2: K8sTrustedRegistries"
print_info "Esta política solo permite imágenes de registries confiables"

# PASO 1: Sin política
print_step "PASO 1: Probando SIN la política aplicada"
print_info "Aplicando Pod con registry no confiable..."
kubectl apply -f manifests/deployments/deployment2_falla.yaml
check_result "Pod creado (no hay política)" "ERROR: No se pudo crear"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-untrusted-registry -o wide
kubectl delete -f manifests/deployments/deployment2_falla.yaml --ignore-not-found=true
print_success "✓ Sin política, cualquier registry es aceptado"

# PASO 2: Aplicar política
print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/2.1.k8sallowedregistries-template.yaml
kubectl apply -f manifests/politicas/2.2.k8sallowedregistries.yaml
wait_for_constraint "trusted-registries-only"

# PASO 3: Intentar pod que falla
print_step "PASO 3: Intentando usar registry NO confiable (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment2_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - registry no está en la lista de confiables"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: El Pod NO fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment2_falla.yaml --ignore-not-found=true
fi

# PASO 4: Pod que cumple
print_step "PASO 4: Usando registry confiable docker.io (debe pasar)"
kubectl apply -f manifests/deployments/deployment2_pasa.yaml
check_result "✓ Pod creado con imagen de registry confiable" "✗ ERROR: Pod bloqueado incorrectamente"

# Verificar
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-trusted-registry -o jsonpath='{.spec.containers[0].image}'
echo ""

# Cleanup
print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment2_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/2.2.k8sallowedregistries.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/2.1.k8sallowedregistries-template.yaml --ignore-not-found=true
print_success "Test completado!"
