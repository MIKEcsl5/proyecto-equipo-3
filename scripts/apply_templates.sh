#!/bin/bash

# Script para aplicar SOLO los ConstraintTemplates (*.1.yaml)
DIRECTORIO="./manifests/politicas"

echo "Iniciando aplicación de ConstraintTemplates..."

# 1. Filtra archivos que terminan en '-template.yaml' o tienen '.1.'
# 2. Ordena numéricamente (1.1, 2.1, ..., 10.1)
ARCHIVOS=$(ls -1 "$DIRECTORIO" | grep -E '\.[1]\..*\.yaml$' | sort -V)

if [ -z "$ARCHIVOS" ]; then
    echo "ERROR: No se encontraron archivos Template (*.1.yaml) en $DIRECTORIO."
    exit 1
fi

echo "Templates a aplicar:"
echo "$ARCHIVOS"
echo "--------------------------------------------------"

for archivo in $ARCHIVOS; do
    RUTA_COMPLETA="$DIRECTORIO/$archivo"
    echo "Aplicando Template: $archivo..."
    kubectl apply -f "$RUTA_COMPLETA"
    if [ $? -ne 0 ]; then
        echo "FALLO: Error al aplicar $archivo. Deteniendo."
        exit 1
    else
        echo "Éxito: $archivo aplicado."
    fi
done

echo "--------------------------------------------------"
echo "Todos los ConstraintTemplates aplicados."
