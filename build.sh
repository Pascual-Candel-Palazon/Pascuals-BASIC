#!/bin/sh
# Construye las tres ROMs desde los fuentes.
# Requisitos: python3, cc65 (ca65/ld65)
set -e
mkdir -p build
cp upstream/m6502.asm src/flatten.py src/translate.py src/kernal.s \
   src/rom.s src/basic.cfg src/c64_build.py build/
cd build
python3 flatten.py
python3 translate.py
ca65 rom.s -l rom_listado.txt -o rom.o
ld65 -C basic.cfg rom.o -o c64_full.bin
python3 c64_build.py
cd ..
cp build/basic_c64.bin build/kernal_c64.bin bin/
echo "ROMs en bin/ — usar con:"
echo "  x64sc -kernal bin/kernal_c64.bin -basic bin/basic_c64.bin -chargen bin/chargen.bin"
