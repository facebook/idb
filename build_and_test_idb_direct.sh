#!/bin/bash

# Build and test script for idb_direct

set -e

echo "Building and testing idb_direct..."

# Build the static library first
echo "1. Building static library..."
./build_idb_direct.sh

# Build the test executable
echo ""
echo "2. Building test executable..."
BUILD_DIR="build/idb_direct_test"
mkdir -p "$BUILD_DIR"

clang \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -I./idb_direct \
    -L./build/lib \
    -lidb_direct \
    -framework Foundation \
    -o "$BUILD_DIR/idb_direct_test" \
    idb_direct/idb_direct_test.m

echo "✅ Test executable built: $BUILD_DIR/idb_direct_test"

# Run the test
echo ""
echo "3. Running smoke test..."
echo ""
"$BUILD_DIR/idb_direct_test" "$@"