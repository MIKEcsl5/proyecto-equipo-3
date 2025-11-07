#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 1: K8sRequiredResources"
print_info "Esta política requiere que todos los contenedores definan resources (requests y limits)"

# PASO 1: Sin política
print_step "PASO 1: Probando SIN la política aplicada"
print_info "Aplicando Pod sin recursos definidos..."
kubectl apply -f manifests/deployments/deployment1_falla.yaml
check_result "Pod creado exitosamente (no hay política que lo bloquee)" "ERROR: No se pudo crear el Pod"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-no-resources -o wide
kubectl delete -f manifests/deployments/deployment1_falla.yaml --ignore-not-found=true
print_success "✓ Sin política, el Pod se crea aunque no tenga recursos definidos"

# PASO 2: Aplicar política
print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/1.1.k8srequiredresources-template.yaml
kubectl apply -f manifests/politicas/1.2.k8srequiredresources.yaml
wait_for_constraint "require-pod-resources"

# PASO 3: Intentar pod que falla
print_step "PASO 3: Intentando crear Pod SIN recursos (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment1_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado correctamente por la política"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: El Pod NO fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment1_falla.yaml --ignore-not-found=true
fi

# PASO 4: Pod que cumple
print_step "PASO 4: Creando Pod CON recursos definidos (debe pasar)"
kubectl apply -f manifests/deployments/deployment1_pasa.yaml
check_result "✓ Pod creado exitosamente con recursos definidos" "✗ ERROR: Pod fue bloqueado incorrectamente"

# Verificar estado
print_step "PASO 5: Verificando el Pod"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-with-resources -o wide

# Cleanup
print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment1_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/1.2.k8srequiredresources.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/1.1.k8srequiredresources-template.yaml --ignore-not-found=true
print_success "Test completado!"
