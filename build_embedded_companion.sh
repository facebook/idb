#!/bin/bash
set -e

# Script to build the embedded idb_companion library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build/embedded"
OUTPUT_DIR="${SCRIPT_DIR}/build/lib"

echo "Building embedded idb_companion library..."

# Create build directories
mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}/include"

# Build frameworks first if needed
if [ ! -d "${SCRIPT_DIR}/build/Build/Products/Debug" ]; then
    echo "Building required frameworks..."
    "${SCRIPT_DIR}/build.sh" framework build
fi

# Compile embedded companion
echo "Compiling idb_direct_embedded.m..."
clang -c \
    -arch arm64 \
    -mmacosx-version-min=11.0 \
    -fobjc-arc \
    -fmodules \
    -std=gnu11 \
    -DDEBUG=1 \
    -I"${SCRIPT_DIR}" \
    -I"${SCRIPT_DIR}/idb_direct" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/FBControlCore.framework/Headers" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/FBSimulatorControl.framework/Headers" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/FBDeviceControl.framework/Headers" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/XCTestBootstrap.framework/Headers" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/CompanionLib.framework/Headers" \
    -I"${SCRIPT_DIR}/build/Build/Products/Debug/IDBCompanionUtilities.framework/Headers" \
    -F"${SCRIPT_DIR}/build/Build/Products/Debug" \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    "${SCRIPT_DIR}/idb_direct/idb_direct_embedded.m" \
    -o "${BUILD_DIR}/idb_direct_embedded.o"

# Create static library
echo "Creating static library..."
ar rcs "${OUTPUT_DIR}/libidb_embedded.a" "${BUILD_DIR}/idb_direct_embedded.o"

# Copy headers
cp "${SCRIPT_DIR}/idb_direct/idb_direct_embedded.h" "${OUTPUT_DIR}/include/"

# Create pkg-config file
cat > "${OUTPUT_DIR}/idb_embedded.pc" << EOF
prefix=${SCRIPT_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/build/lib
includedir=\${prefix}/build/lib/include

Name: idb_embedded
Description: Embedded IDB Companion Library
Version: 1.0.0
Libs: -L\${libdir} -lidb_embedded -framework Foundation -framework CoreGraphics
Libs.private: -F${SCRIPT_DIR}/build/Build/Products/Debug -framework FBControlCore -framework FBSimulatorControl -framework FBDeviceControl -framework XCTestBootstrap -framework CompanionLib -framework IDBCompanionUtilities
Cflags: -I\${includedir}
EOF

echo "Embedded companion library built successfully!"
echo "Library: ${OUTPUT_DIR}/libidb_embedded.a"
echo "Header: ${OUTPUT_DIR}/include/idb_direct_embedded.h"

# Build test program if requested
if [ "$1" == "test" ]; then
    echo "Building test program..."
    cat > "${BUILD_DIR}/test_embedded.m" << 'EOF'
#import <Foundation/Foundation.h>
#import "idb_direct_embedded.h"

void log_callback(const char* message, int level, void* context) {
    printf("[LOG %d] %s\n", level, message);
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        printf("Testing embedded companion...\n");
        
        // Create companion
        idb_companion_handle_t* companion = NULL;
        idb_error_t result = idb_companion_create(&companion);
        if (result != IDB_SUCCESS) {
            printf("Failed to create companion: %s\n", idb_companion_error_string(result));
            return 1;
        }
        
        printf("Companion version: %s\n", idb_companion_version());
        
        // Set log callback
        idb_companion_set_log_callback(companion, log_callback, NULL);
        
        // List targets (simulators)
        if (argc > 1) {
            const char* udid = argv[1];
            printf("Connecting to simulator %s...\n", udid);
            
            result = idb_companion_connect(companion, udid, IDB_TARGET_SIMULATOR);
            if (result == IDB_SUCCESS) {
                printf("Connected successfully!\n");
                
                // List apps
                char** bundle_ids = NULL;
                size_t count = 0;
                result = idb_companion_list_apps(companion, &bundle_ids, &count);
                if (result == IDB_SUCCESS) {
                    printf("Found %zu apps:\n", count);
                    for (size_t i = 0; i < count && i < 10; i++) {
                        printf("  - %s\n", bundle_ids[i]);
                    }
                    idb_companion_free_app_list(bundle_ids, count);
                }
                
                // Take screenshot
                uint8_t* data = NULL;
                size_t size = 0;
                uint32_t width = 0, height = 0;
                result = idb_companion_screenshot(companion, &data, &size, &width, &height);
                if (result == IDB_SUCCESS) {
                    printf("Screenshot taken: %zu bytes\n", size);
                    idb_companion_free_screenshot(data);
                }
                
                idb_companion_disconnect(companion);
            } else {
                printf("Failed to connect: %s\n", idb_companion_error_string(result));
            }
        }
        
        // Cleanup
        idb_companion_destroy(companion);
        
        printf("Test completed.\n");
        return 0;
    }
}
EOF

    clang \
        -arch arm64 \
        -mmacosx-version-min=11.0 \
        -fobjc-arc \
        -I"${OUTPUT_DIR}/include" \
        -L"${OUTPUT_DIR}" \
        -F"${SCRIPT_DIR}/build/Build/Products/Debug" \
        -framework Foundation \
        -framework CoreGraphics \
        -framework FBControlCore \
        -framework FBSimulatorControl \
        -framework FBDeviceControl \
        -framework XCTestBootstrap \
        -framework CompanionLib \
        -framework IDBCompanionUtilities \
        -lidb_embedded \
        "${BUILD_DIR}/test_embedded.m" \
        -o "${BUILD_DIR}/test_embedded"
    
    echo "Test program built: ${BUILD_DIR}/test_embedded"
    echo "Usage: ${BUILD_DIR}/test_embedded <simulator-udid>"
fi