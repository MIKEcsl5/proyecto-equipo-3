#!/bin/bash

# Script para aplicar SOLO los Constraints (*.2.yaml)
DIRECTORIO="/root/opa_gatekeeper/politicas"
NAMESPACE_ARG="" # Puedes añadir manejo de namespace aquí si lo necesitas

echo "Iniciando aplicación de Constraints..."

# 1. Filtra archivos que contienen '.2.'
# 2. Ordena numéricamente (1.2, 2.2, ..., 10.2)
ARCHIVOS=$(ls -1 "$DIRECTORIO" | grep -E '\.[2]\..*\.yaml$' | sort -V)

if [ -z "$ARCHIVOS" ]; then
    echo "ERROR: No se encontraron archivos Constraint (*.2.yaml) en $DIRECTORIO."
    exit 1
fi

echo "Constraints a aplicar:"
echo "$ARCHIVOS"
echo "--------------------------------------------------"

for archivo in $ARCHIVOS; do
    RUTA_COMPLETA="$DIRECTORIO/$archivo"
    echo "Aplicando Constraint: $archivo..."
    # Se usa -f y el argumento de namespace opcional
    kubectl apply -f "$RUTA_COMPLETA" $NAMESPACE_ARG
    if [ $? -ne 0 ]; then
        echo "FALLO: Error al aplicar $archivo. Deteniendo."
        exit 1
    else
        echo "Éxito: $archivo aplicado."
    fi
done

echo "--------------------------------------------------"
echo "Todos los Constraints aplicados."
