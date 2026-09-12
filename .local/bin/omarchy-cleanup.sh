#!/bin/bash

echo "╔══════════════════════════════╗"
echo "║     Limpieza del sistema     ║"
echo "╚══════════════════════════════╝"
echo ""

# Caché de paquetes: borrar versiones antiguas (mantiene la más reciente)
echo "→ Limpiando caché de paquetes de pacman..."
sudo pacman -Sc --noconfirm
echo ""

# Paquetes huérfanos
orphans=$(pacman -Qtdq 2>/dev/null)
if [ -n "$orphans" ]; then
    echo "→ Paquetes huérfanos encontrados:"
    echo "$orphans"
    echo ""
    read -rp "¿Eliminarlos? [s/N] " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        sudo pacman -Rns $orphans
    else
        echo "Omitido."
    fi
else
    echo "→ No hay paquetes huérfanos."
fi

echo ""
echo "✓ Limpieza completada."
echo ""
read -rp "Pulsa Enter para cerrar..."
