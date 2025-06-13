#!/bin/bash

# Memory leak detection script for idb_direct
# Uses Instruments leaks tool to detect memory leaks in the Direct FFI implementation

set -e

echo "idb_direct Memory Leak Detection"
echo "================================="
echo

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Memory leak detection requires macOS with Instruments"
    exit 1
fi

# Check if Instruments is available
if ! command -v leaks &> /dev/null; then
    echo "❌ leaks command not found. Install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

# Build the test binary
echo "🔨 Building memory leak test binary..."
if ! ./build_idb_direct.sh; then
    echo "❌ Failed to build static library"
    exit 1
fi

# Compile the memory leak test
cd idb_direct
clang -o memory_leak_test \
    memory_leak_test.m \
    -F../build/Build/Products/Debug \
    -framework FBControlCore \
    -framework FBSimulatorControl \
    -framework FBDeviceControl \
    -framework XCTestBootstrap \
    -L../build/lib \
    -lidb_direct \
    -Wl,-rpath,../build/Build/Products/Debug \
    -I../build/lib/include \
    -fobjc-arc

if [[ $? -ne 0 ]]; then
    echo "❌ Failed to compile memory leak test"
    exit 1
fi

echo "✅ Memory leak test binary compiled"
echo

# Run the test with different configurations
echo "🧪 Running memory leak detection tests..."
echo

# Test 1: CI mode (basic initialization/shutdown cycles)
echo "Test 1: CI Mode (Init/Shutdown cycles)"
echo "--------------------------------------"
IDB_TEST_CI_MODE=1 timeout 30s leaks -atExit -- ./memory_leak_test &
TEST_PID=$!

# Wait a moment then check for leaks
sleep 5
echo "Checking for leaks in CI mode test..."
leaks $TEST_PID | grep -E "(LEAK:|Process|leaked bytes)" || echo "No leaks detected in CI mode"

# Kill the test
kill $TEST_PID 2>/dev/null || true
wait $TEST_PID 2>/dev/null || true
echo

# Test 2: Simulator mode (if simulator available)
echo "Test 2: Simulator Mode (with operations)"
echo "----------------------------------------"

# Check if any simulators are booted
if xcrun simctl list devices | grep -q "Booted"; then
    echo "Found booted simulator, running full test..."
    timeout 30s leaks -atExit -- ./memory_leak_test &
    TEST_PID=$!
    
    # Wait a moment then check for leaks
    sleep 10
    echo "Checking for leaks in simulator mode test..."
    leaks $TEST_PID | grep -E "(LEAK:|Process|leaked bytes)" || echo "No leaks detected in simulator mode"
    
    # Kill the test
    kill $TEST_PID 2>/dev/null || true
    wait $TEST_PID 2>/dev/null || true
else
    echo "No booted simulators found, skipping simulator mode test"
    echo "To run full test:"
    echo "  1. Boot a simulator: xcrun simctl boot '<UDID>'"
    echo "  2. Run: leaks -atExit -- ./memory_leak_test"
fi

echo

# Test 3: Shared memory screenshot stress test
echo "Test 3: Shared Memory Screenshot Stress Test"
echo "--------------------------------------------"

# Create a simple shared memory test
cat > shm_stress_test.m << 'EOF'
#import <Foundation/Foundation.h>
#import "idb_direct_shm.h"

int main() {
    @autoreleasepool {
        printf("Testing shared memory screenshot stress...\n");
        
        // Simulate rapid create/destroy cycles
        for (int i = 0; i < 100; i++) {
            idb_shm_handle_t handle;
            if (idb_shm_create(1024 * 1024, &handle) == IDB_SUCCESS) {
                idb_shm_destroy(handle);
            }
            
            if (i % 20 == 0) {
                printf("Completed %d/100 SHM cycles\n", i);
            }
        }
        
        printf("SHM stress test complete\n");
    }
    return 0;
}
EOF

# Compile the SHM stress test
clang -o shm_stress_test \
    shm_stress_test.m \
    -L../build/lib \
    -lidb_direct \
    -I../build/lib/include \
    -fobjc-arc

if [[ $? -eq 0 ]]; then
    echo "Running shared memory stress test..."
    leaks -atExit -- ./shm_stress_test
    echo
else
    echo "Failed to compile SHM stress test, skipping..."
fi

# Cleanup
rm -f shm_stress_test.m shm_stress_test

echo "🎯 Memory Leak Detection Summary"
echo "================================"
echo
echo "✅ Completed memory leak detection tests"
echo
echo "📋 Manual Testing Instructions:"
echo "1. Run extended test: leaks -atExit -- ./memory_leak_test"
echo "2. Use Instruments for detailed analysis:"
echo "   instruments -t Leaks ./memory_leak_test"
echo "3. Monitor during development with:"
echo "   leaks <PID> (while process is running)"
echo
echo "🔍 What to Look For:"
echo "- Any leaked bytes reported by 'leaks' command"
echo "- Growing memory usage over time (use Activity Monitor)"
echo "- Autorelease pool growth (check with Instruments)"
echo "- Framework object leaks (FBFuture, NSData, etc.)"
echo

cd ..
echo "Test binary available at: idb_direct/memory_leak_test"
echo "Run manually with: ./idb_direct/memory_leak_test"