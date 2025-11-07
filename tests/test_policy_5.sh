#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 5: K8sReadOnlyRootFS"
print_info "Esta política requiere que el filesystem raíz sea de solo lectura"

print_step "PASO 1: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment5_falla.yaml
check_result "Pod sin readOnlyRootFilesystem creado" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-no-readonly-fs -o wide
kubectl delete -f manifests/deployments/deployment5_falla.yaml --ignore-not-found=true

print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/5.1.readOnlyRootFilesystem.yaml
kubectl apply -f manifests/politicas/5.2.k8sreadonlyrootfs.yaml
wait_for_constraint "enforce-readonly-rootfs"

print_step "PASO 3: Intentando Pod sin readOnlyRootFilesystem (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment5_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod bloqueado - filesystem debe ser read-only"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment5_falla.yaml --ignore-not-found=true
fi

print_step "PASO 4: Creando Pod con readOnlyRootFilesystem (debe pasar)"
kubectl apply -f manifests/deployments/deployment5_pasa.yaml
check_result "✓ Pod con filesystem read-only creado" "✗ ERROR"

print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-readonly-fs -o wide

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment5_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/5.2.k8sreadonlyrootfs.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/5.1.readOnlyRootFilesystem.yaml --ignore-not-found=true
print_success "Test completado!"
