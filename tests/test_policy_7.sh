#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 7: K8sSecurityContext"
print_info "Esta política requiere securityContext y prohíbe ejecutar como root"

print_step "PASO 1: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment7_falla.yaml
check_result "Pod sin securityContext creado" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-no-security-context -o wide
kubectl delete -f manifests/deployments/deployment7_falla.yaml --ignore-not-found=true

print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/7.1.k8ssecuritycontext-template.yaml
kubectl apply -f manifests/politicas/7.2.k8ssecuritycontext.yaml
wait_for_constraint "validate-securitycontext"

print_step "PASO 3a: Intentando Pod SIN securityContext (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment7_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - falta securityContext"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment7_falla.yaml --ignore-not-found=true
fi

print_step "PASO 3b: Intentando Pod ejecutando como root (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment7_falla2.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - runAsUser: 0 no permitido"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment7_falla2.yaml --ignore-not-found=true
fi

print_step "PASO 4: Creando Pod con securityContext correcto (debe pasar)"
kubectl apply -f manifests/deployments/deployment7_pasa2.yaml
check_result "✓ Pod con securityContext válido creado" "✗ ERROR"

print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-good-security-context -o wide

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment7_pasa2.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/7.2.k8ssecuritycontext.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/7.1.k8ssecuritycontext-template.yaml --ignore-not-found=true
print_success "Test completado!"
