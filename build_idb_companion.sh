#!/bin/bash

# Build script for libidb_direct.a with CompanionLib integration

set -e

echo "Building libidb_direct.a with CompanionLib integration..."

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

# First, compile FBIDBEmbeddedServer
echo "Compiling FBIDBEmbeddedServer..."
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./CompanionLib \
    -I./IDBCompanionUtilities \
    -I./PrivateHeaders \
    -I./FBControlCore \
    -I./FBSimulatorControl \
    -I./FBDeviceControl \
    -I./XCTestBootstrap \
    -F"$FRAMEWORK_DIR" \
    -o "$BUILD_DIR/FBIDBEmbeddedServer.o" \
    CompanionLib/FBIDBEmbeddedServer.m

# Compile FBIDBCommandExecutor
echo "Compiling FBIDBCommandExecutor..."
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./CompanionLib \
    -I./IDBCompanionUtilities \
    -I./PrivateHeaders \
    -I./FBControlCore \
    -I./FBSimulatorControl \
    -I./FBDeviceControl \
    -I./XCTestBootstrap \
    -F"$FRAMEWORK_DIR" \
    -o "$BUILD_DIR/FBIDBCommandExecutor.o" \
    CompanionLib/FBIDBCommandExecutor.m

# Compile FBIDBStorageManager
echo "Compiling FBIDBStorageManager..."
clang -c \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -I./CompanionLib \
    -I./IDBCompanionUtilities \
    -I./PrivateHeaders \
    -I./FBControlCore \
    -I./FBSimulatorControl \
    -I./FBDeviceControl \
    -I./XCTestBootstrap \
    -F"$FRAMEWORK_DIR" \
    -o "$BUILD_DIR/FBIDBStorageManager.o" \
    CompanionLib/Utility/FBIDBStorageManager.m

# Compile other required CompanionLib files
echo "Compiling other CompanionLib components..."
for file in CompanionLib/Reporting/FBIDBError.m CompanionLib/Utility/FBIDBLogger.m CompanionLib/Utility/FBIDBTestOperation.m; do
    if [ -f "$file" ]; then
        basename=$(basename "$file" .m)
        echo "  - $basename"
        clang -c \
            -arch arm64 \
            -mmacosx-version-min=13.0 \
            -fobjc-arc \
            -fmodules \
            -I./CompanionLib \
            -I./IDBCompanionUtilities \
            -I./PrivateHeaders \
            -I./FBControlCore \
            -I./FBSimulatorControl \
            -I./FBDeviceControl \
            -I./XCTestBootstrap \
            -F"$FRAMEWORK_DIR" \
            -o "$BUILD_DIR/$basename.o" \
            "$file"
    fi
done

# Compile idb_direct_companion.m
echo "Compiling idb_direct_companion..."
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
    -o "$BUILD_DIR/idb_direct_companion.o" \
    idb_direct/idb_direct_companion.m

# Create static library with all objects
echo "Creating static library..."
ar rcs "$OUTPUT_DIR/libidb_direct.a" "$BUILD_DIR"/*.o

# Copy header
mkdir -p "$OUTPUT_DIR/include"
cp idb_direct/idb_direct.h "$OUTPUT_DIR/include/"

echo "✅ Static library built: $OUTPUT_DIR/libidb_direct.a"
echo "✅ Header file: $OUTPUT_DIR/include/idb_direct.h"

# Show library info
lipo -info "$OUTPUT_DIR/libidb_direct.a"
echo ""
echo "Objects in library:"
ar -t "$OUTPUT_DIR/libidb_direct.a"