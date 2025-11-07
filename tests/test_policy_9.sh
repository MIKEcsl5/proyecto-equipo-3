#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 9: K8sRequiredProbes"
print_info "Esta política requiere livenessProbe y readinessProbe"

print_step "PASO 1: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment9_falla.yaml
check_result "Pod sin probes creado" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-no-probes -o wide
kubectl delete -f manifests/deployments/deployment9_falla.yaml --ignore-not-found=true

print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/9.1.k8srequiredprobes-template.yaml
kubectl apply -f manifests/politicas/9.2.k8srequiredprobes.yaml
wait_for_constraint "require-probes"

print_step "PASO 3a: Intentando Pod SIN probes (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment9_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - faltan ambos probes"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment9_falla.yaml --ignore-not-found=true
fi

print_step "PASO 3b: Intentando Pod solo con livenessProbe (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment9_falla2.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - falta readinessProbe"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment9_falla2.yaml --ignore-not-found=true
fi

print_step "PASO 4: Creando Pod con ambos probes (debe pasar)"
kubectl apply -f manifests/deployments/deployment9_pasa.yaml
check_result "✓ Pod con liveness y readiness probes creado" "✗ ERROR"

print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-with-probes -o wide

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment9_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/9.2.k8srequiredprobes.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/9.1.k8srequiredprobes-template.yaml --ignore-not-found=true
print_success "Test completado!"
