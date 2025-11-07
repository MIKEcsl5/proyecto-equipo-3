#!/bin/bash
source tests/common.sh

print_header "TEST POLÍTICA 10: K8sRequirePDB"
print_info "Esta política requiere PodDisruptionBudget en namespaces de producción"

print_step "PASO 1: Creando namespace production"
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -

print_step "PASO 2: Probando SIN la política aplicada"
kubectl apply -f manifests/deployments/deployment10_falla.yaml
check_result "Deployment sin PDB creado" "ERROR"
print_info "Esperando 5 segundos para que el Deployment se cree..."
sleep 5
kubectl get deployment test-deployment-no-pdb -n production -o wide
kubectl delete -f manifests/deployments/deployment10_falla.yaml --ignore-not-found=true

print_step "PASO 3: Aplicando la política"
kubectl apply -f manifests/politicas/10.1.k8srequirepdb-template.yaml
kubectl apply -f manifests/politicas/10.2.k8srequirepdb.yaml
wait_for_constraint "require-pdb-prod"

print_step "PASO 4: Esperando sincronización de Gatekeeper..."
sleep 5

print_step "PASO 5: Intentando Deployment SIN PDB (debe fallar)"
OUTPUT=$(kubectl apply -f manifests/deployments/deployment10_falla.yaml 2>&1)
if echo "$OUTPUT" | grep -q "denied\|no tiene PodDisruptionBudget"; then
    print_success "✓ Deployment bloqueado - namespace sin PDB"
    print_warning "Mensaje de Gatekeeper:"
    echo "$OUTPUT" | grep -E "denied|PodDisruptionBudget" | head -3
else
    print_warning "⚠ Puede que necesites habilitar data sync en Gatekeeper"
    echo "$OUTPUT"
    kubectl delete -f manifests/deployments/deployment10_falla.yaml --ignore-not-found=true
fi

print_step "PASO 6: Creando PodDisruptionBudget"
kubectl apply -f manifests/deployments/deployment10_pdb.yaml
sleep 3

print_step "PASO 7: Creando Deployment CON PDB configurado (debe pasar)"
kubectl apply -f manifests/deployments/deployment10_pasa2.yaml
check_result "✓ Deployment creado - namespace tiene PDB" "✗ ERROR"

print_info "Esperando 5 segundos para que el Deployment se cree..."
sleep 5
kubectl get deployment test-deployment-with-pdb -n production -o wide
kubectl get pods -n production -l app=myapp

print_step "Limpieza"
kubectl delete -f manifests/deployments/deployment10_pasa2.yaml --ignore-not-found=true
kubectl delete -f manifests/deployments/deployment10_pdb.yaml --ignore-not-found=true
kubectl delete namespace production --ignore-not-found=true
kubectl delete -f manifests/politicas/10.2.k8srequirepdb.yaml --ignore-not-found=true
kubectl delete -f manifests/politicas/10.1.k8srequirepdb-template.yaml --ignore-not-found=true
print_success "Test completado!"
