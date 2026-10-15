#!/bin/bash
# Compila o lançador (Lacador.exe sem o conteúdo) com o MinGW-w64, para Windows de 64 bits.
# A arte da abertura (abertura.jpg) vai dentro, como recurso.
set -e
cd "$(dirname "$0")"
cp ../Lacador/programa/interface/img/lacador.ico .
x86_64-w64-mingw32-windres -c 65001 lacador.rc -O coff -o lacador.res.o
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -mwindows -static -s lacador.c abertura.c lacador.res.o -o lancador.exe -lshell32 -lgdiplus -lshlwapi -lole32
ls -la lancador.exe
