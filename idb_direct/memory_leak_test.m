/*
 * Memory leak test for idb_direct
 * Exercises the main API functions in a loop to detect memory leaks
 * Run with Instruments: leaks -atExit -- ./memory_leak_test
 */

#import <Foundation/Foundation.h>
#import "idb_direct.h"

// Test configuration
#define LOOP_COUNT 1000
#define SCREENSHOT_INTERVAL 10  // Take screenshot every 10th iteration
#define AUTORELEASE_INTERVAL 100  // Drain autorelease pool every 100 iterations

int main(int argc, const char * argv[]) {
    printf("idb_direct Memory Leak Test\n");
    printf("===========================\n\n");
    
    // Check if CI mode (skip operations that require simulator)
    BOOL ci_mode = getenv("IDB_TEST_CI_MODE") != NULL;
    if (ci_mode) {
        printf("Running in CI mode - testing initialization/shutdown only\n");
    }
    
    // Track memory at start
    printf("Starting memory leak test with %d iterations...\n", LOOP_COUNT);
    printf("Monitor with: leaks %d\n\n", getpid());
    
    for (int i = 0; i < LOOP_COUNT; i++) {
        @autoreleasepool {
            // Initialize
            idb_error_t result = idb_initialize();
            if (result != IDB_SUCCESS && result != IDB_ERROR_NOT_INITIALIZED) {
                if (!ci_mode) {
                    printf("Iteration %d: Initialize failed: %s\n", i, idb_error_string(result));
                    continue;
                }
            }
            
            if (!ci_mode) {
                // Try to perform basic operations if not in CI mode
                
                // Test tap operation (will fail without simulator, but exercises memory paths)
                idb_tap(100.0, 200.0);
                
                // Test screenshot operation every SCREENSHOT_INTERVAL iterations
                if (i % SCREENSHOT_INTERVAL == 0) {
                    idb_screenshot_t screenshot;
                    idb_error_t result = idb_take_screenshot(&screenshot);
                    if (result == IDB_SUCCESS) {
                        idb_free_screenshot(&screenshot);
                    }
                }
            }
            
            // Shutdown
            idb_shutdown();
            
            // Progress indicator
            if (i % 100 == 0) {
                printf("Completed %d/%d iterations\n", i, LOOP_COUNT);
            }
        }
        
        // Manually drain autorelease pool periodically for better memory tracking
        if (i % AUTORELEASE_INTERVAL == 0) {
            @autoreleasepool {
                // Force autorelease pool drain
            }
        }
    }
    
    printf("\nCompleted %d iterations\n", LOOP_COUNT);
    printf("Run 'leaks %d' to check for memory leaks\n", getpid());
    printf("Press Ctrl+C to exit and generate final leak report\n");
    
    // Keep process alive for leak analysis
    while (1) {
        sleep(1);
    }
    
    return 0;
}