#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 6: K8sBlockHostPath"
print_info "Esta política bloquea el uso de volúmenes hostPath"

print_step "PASO 1: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment6_falla.yaml
check_result "Pod con hostPath creado" "ERROR"
print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-with-hostpath -o wide
kubectl delete -f manifests/deployments/deployment6_falla.yaml --ignore-not-found=true

print_step "PASO 2: Aplicando la política"
kubectl apply -f manifests/politicas/6.1.k8sblockhostpath-template.yaml
kubectl apply -f manifests/politicas/6.2.k8sblockhostpath.yaml
wait_for_constraint "disallow-hostpath"

print_step "PASO 3: Intentando Pod con hostPath (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment6_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied"; then
    print_success "✓ Pod con hostPath bloqueado correctamente"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -A 2 "denied"
else
    print_error "✗ ERROR: No fue bloqueado"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment6_falla.yaml --ignore-not-found=true
fi

print_step "PASO 4: Creando Pod con emptyDir en vez de hostPath (debe pasar)"
kubectl apply -f manifests/deployments/deployment6_pasa.yaml
check_result "✓ Pod con emptyDir creado exitosamente" "✗ ERROR"

print_info "Esperando 5 segundos para que el Pod se cree..."
sleep 5
kubectl get pod test-without-hostpath -o wide

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment6_pasa.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/6.2.k8sblockhostpath.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/6.1.k8sblockhostpath-template.yaml --ignore-not-found=true
print_success "Test completado!"
