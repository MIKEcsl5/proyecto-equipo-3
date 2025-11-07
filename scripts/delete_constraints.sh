#!/bin/bash

# Script para eliminar SOLO los Constraints (*.2.yaml)
DIRECTORIO="./manifests/politicas"
NAMESPACE_ARG=""

echo "Iniciando eliminación de Constraints..."

# 1. Filtra archivos que contienen '.2.'
# 2. Ordena INVERSAMENTE (10.2, 9.2, ..., 1.2)
ARCHIVOS=$(ls -1 "$DIRECTORIO" | grep -E '\.[2]\..*\.yaml$' | sort -Vr)

if [ -z "$ARCHIVOS" ]; then
    echo "ERROR: No se encontraron archivos Constraint (*.2.yaml) en $DIRECTORIO."
    exit 1
fi

echo "Constraints a eliminar (orden inverso):"
echo "$ARCHIVOS"
echo "--------------------------------------------------"

for archivo in $ARCHIVOS; do
    RUTA_COMPLETA="$DIRECTORIO/$archivo"
    echo "Eliminando Constraint: $archivo..."
    # Usamos delete -f. El script continúa intentando aunque falle (quitamos 'exit 1')
    kubectl delete -f "$RUTA_COMPLETA" $NAMESPACE_ARG
    if [ $? -ne 0 ]; then
        echo "FALLO: Error al eliminar $archivo. Continuar..."
    else
        echo "Éxito: $archivo eliminado."
    fi
done

echo "--------------------------------------------------"
echo "Proceso de eliminación de Constraints finalizado."
