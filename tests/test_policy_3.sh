#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 3: K8sRequiredLabels"
print_info "Esta política requiere labels específicos: app, environment, owner, version"

# PASO 1: Sin política
print_step "PASO 1: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment3_falla.yaml
check_result "Pod creado sin labels requeridos" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-missing-labels -o wide --show-labels
kubectl delete -f manifests/deployments/deployment3_falla.yaml --ignore-not-found=true
print_success "✓ Sin política, los labels no son validados"

# PASO 2: Aplicar política
print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/3.1.k8srequiredlabels-template.yaml
kubectl apply -f manifests/politicas/3.2.k8srequiredlabels.yaml
wait_for_constraint "required-labels-policy"

# PASO 3: Faltan labels
print_step "PASO 3: Intentando crear Pod sin labels completos (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment3_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - faltan labels requeridos"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment3_falla.yaml --ignore-not-found=true
fi

# PASO 3b: Labels con valores inválidos
print_step "PASO 3b: Intentando label 'environment' con valor inválido (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment3_falla2.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - 'environment: testing' no cumple regex"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment3_falla2.yaml --ignore-not-found=true
fi

# PASO 4: Pod correcto
print_step "PASO 4: Creando Pod con todos los labels correctos (debe pasar)"
kubectl apply -f manifests/deployments/deployment3_pasa.yaml
check_result "✓ Pod creado con labels válidos" "✗ ERROR"

# Mostrar labels
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-with-labels --show-labels

# Cleanup
print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment3_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/3.2.k8srequiredlabels.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/3.1.k8srequiredlabels-template.yaml --ignore-not-found=true
print_success "Test completado!"
