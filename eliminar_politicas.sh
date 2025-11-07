#!/bin/bash

# --- Script para aplicar archivos YAML de Kubernetes en orden numérico ---

# --- Configuración de la Ruta Fija ---
DIRECTORIO="/root/opa_gatekeeper/politicas"

# --- Búsqueda y Ordenamiento de Archivos ---
# Cambiar al directorio para encontrar los archivos
if ! cd "$DIRECTORIO"; then
    echo "ERROR: No se pudo acceder al directorio $DIRECTORIO."
    exit 1
fi

# Filtra archivos *.yaml y los ordena de forma natural (1.x, 2.x, ..., 10.x)
ARCHIVOS=$(ls -1 | grep '\.yaml$' | sort -Vr)

if [ -z "$ARCHIVOS" ]; then
    echo "ERROR: No se encontraron archivos YAML para aplicar en $DIRECTORIO."
    exit 1
fi

echo "Archivos a eliminar en orden numérico:"
echo "$ARCHIVOS"
echo "--------------------------------------------------"

# --- Bucle de Aplicación ---
for archivo in $ARCHIVOS; do
    echo "Eliminando: $archivo $NAMESPACE_ARG..."
    # Ejecuta kubectl apply con la ruta y el argumento del namespace
    kubectl delete -f "$archivo" $NAMESPACE_ARG

    if [ $? -ne 0 ]; then
        echo "FALLO: Error al eliminar $archivo. Deteniendo el script."
    else
        echo "Éxito: $archivo eliminado correctamente."
    fi
done

echo "--------------------------------------------------"
echo "Todos los archivos han sido eliminados."
