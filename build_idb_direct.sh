#!/bin/bash

# Simple build script for libidb_direct.a

set -e

echo "Building libidb_direct.a static library..."

# Build directory
BUILD_DIR="build/idb_direct"
OUTPUT_DIR="build/lib"
FRAMEWORK_DIR="build/Build/Products/Debug"

# Check if frameworks are built
if [ ! -d "$FRAMEWORK_DIR/FBControlCore.framework" ]; then
    echo "Error: Frameworks not found. Please build them first with:"
    echo "  ./build.sh framework build"
    exit 1
fi

# Clean and create directories
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# Compile idb_direct.m to object file
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./idb_direct \
    -I./CompanionLib \
    -I./IDBCompanionUtilities \
    -I./PrivateHeaders \
    -I./FBControlCore \
    -I./FBSimulatorControl \
    -I./FBDeviceControl \
    -I./XCTestBootstrap \
    -F"$FRAMEWORK_DIR" \
    -o "$BUILD_DIR/idb_direct.o" \
    idb_direct/idb_direct_real_adaptive.m

# Compile stubs
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./idb_direct \
    -o "$BUILD_DIR/idb_direct_stubs.o" \
    idb_direct/idb_direct_stubs.m

# Compile shared memory implementation
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./idb_direct \
    -o "$BUILD_DIR/idb_direct_shm.o" \
    idb_direct/idb_direct_shm.m

# Create static library with all objects
ar rcs "$OUTPUT_DIR/libidb_direct.a" "$BUILD_DIR/idb_direct.o" "$BUILD_DIR/idb_direct_stubs.o" "$BUILD_DIR/idb_direct_shm.o"

# Copy headers
mkdir -p "$OUTPUT_DIR/include"
cp idb_direct/idb_direct.h "$OUTPUT_DIR/include/"
cp idb_direct/idb_direct_extended.h "$OUTPUT_DIR/include/"
cp idb_direct/idb_direct_shm.h "$OUTPUT_DIR/include/"

echo "✅ Static library built: $OUTPUT_DIR/libidb_direct.a"
echo "✅ Header file: $OUTPUT_DIR/include/idb_direct.h"

# Show library info
lipo -info "$OUTPUT_DIR/libidb_direct.a"