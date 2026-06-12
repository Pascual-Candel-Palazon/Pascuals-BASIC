#!/bin/sh
# Corre toda la bateria de tests. Requiere ../build (./build.sh) o ../bin.
set -e
for t in test_humo.py test_teclado.py test_basic.py test_editor.py test_stop.py test_color.py test_modes.py; do
    echo "=== $t ==="
    python3 "$t"
done
echo "=== TODO EN VERDE ==="
