#!/bin/bash

# Script para eliminar SOLO los ConstraintTemplates (*.1.yaml)
DIRECTORIO="./manifests/politicas"

echo "Iniciando eliminación de ConstraintTemplates..."

# 1. Filtra archivos que contienen '.1.'
# 2. Ordena INVERSAMENTE (10.1, 9.1, ..., 1.1)
ARCHIVOS=$(ls -1 "$DIRECTORIO" | grep -E '\.[1]\..*\.yaml$' | sort -Vr)

if [ -z "$ARCHIVOS" ]; then
    echo "ERROR: No se encontraron archivos Template (*.1.yaml) en $DIRECTORIO."
    exit 1
fi

echo "Templates a eliminar (orden inverso):"
echo "$ARCHIVOS"
echo "--------------------------------------------------"

for archivo in $ARCHIVOS; do
    RUTA_COMPLETA="$DIRECTORIO/$archivo"
    echo "Eliminando Template: $archivo..."
    # El script continúa intentando aunque falle
    kubectl delete -f "$RUTA_COMPLETA"
    if [ $? -ne 0 ]; then
        echo "FALLO: Error al eliminar $archivo. Continuar..."
    else
        echo "Éxito: $archivo eliminado."
    fi
done

echo "--------------------------------------------------"
echo "Proceso de eliminación de ConstraintTemplates finalizado."
