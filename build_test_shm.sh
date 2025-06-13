#!/bin/bash

# Build test program for shared memory screenshots

set -e

echo "Building shared memory test..."

# Build the library first
./build_idb_direct.sh

# Compile test program
clang \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -framework Foundation \
    -framework CoreGraphics \
    -framework ImageIO \
    -I./build/lib/include \
    -L./build/lib \
    -lidb_direct \
    -o build/test_shm \
    idb_direct/test_shm.m

echo "✅ Test program built: build/test_shm"
echo ""
echo "To run the test:"
echo "  ./build/test_shm"