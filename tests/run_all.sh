#!/bin/sh
# Corre toda la bateria de tests. Requiere ../build (./build.sh) o ../bin.
set -e
for t in test_humo.py test_teclado.py test_basic.py test_editor.py test_stop.py test_color.py test_modes.py test_keymods.py test_ctrlcodes.py test_case.py test_vectores.py test_iec_fase1.py test_iec_fase2a.py test_iec_fase3parse.py; do
    echo "=== $t ==="
    python3 "$t"
done
echo "=== TODO EN VERDE ==="
