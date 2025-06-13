/*
 * Test program for shared memory screenshot functionality
 */

#import <Foundation/Foundation.h>
#import <unistd.h>
#import "idb_direct.h"
#import "idb_direct_shm.h"

static void screenshot_callback(const idb_shm_screenshot_t* screenshot, void* context) {
    static int frame_count = 0;
    frame_count++;
    
    printf("Frame %d: %ux%u, %zu bytes, format: %s, shm_key: %s\n",
           frame_count,
           screenshot->width,
           screenshot->height,
           screenshot->size,
           screenshot->format,
           idb_shm_get_key(screenshot->handle));
    
    // Verify we can read the data
    if (screenshot->base_address) {
        uint32_t* pixels = (uint32_t*)screenshot->base_address;
        uint32_t first_pixel = pixels[0];
        uint32_t center_pixel = pixels[(screenshot->height/2) * (screenshot->bytes_per_row/4) + screenshot->width/2];
        printf("  First pixel: 0x%08X, Center pixel: 0x%08X\n", first_pixel, center_pixel);
    }
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        printf("=== IDB Direct Shared Memory Screenshot Test ===\n\n");
        
        // Initialize
        printf("Initializing IDB...\n");
        idb_error_t err = idb_initialize();
        if (err != IDB_SUCCESS) {
            printf("Failed to initialize: %s\n", idb_error_string(err));
            return 1;
        }
        
        // List available targets
        idb_target_info_t* targets = NULL;
        size_t count = 0;
        err = idb_list_targets(&targets, &count);
        if (err != IDB_SUCCESS || count == 0) {
            printf("No simulators found\n");
            return 1;
        }
        
        printf("Found %zu simulators\n", count);
        
        // Find a booted simulator
        const char* target_udid = NULL;
        for (size_t i = 0; i < count; i++) {
            if (targets[i].is_running) {
                target_udid = targets[i].udid;
                printf("Using booted simulator: %s (%s)\n", targets[i].name, targets[i].udid);
                break;
            }
        }
        
        if (!target_udid) {
            printf("No booted simulator found\n");
            idb_free_targets(targets, count);
            return 1;
        }
        
        // Connect to target
        err = idb_connect_target(target_udid, IDB_TARGET_SIMULATOR);
        idb_free_targets(targets, count);
        
        if (err != IDB_SUCCESS) {
            printf("Failed to connect: %s\n", idb_error_string(err));
            return 1;
        }
        
        // Test 1: Single shared memory screenshot
        printf("\n--- Test 1: Single Screenshot ---\n");
        idb_shm_screenshot_t screenshot = {0};
        err = idb_take_screenshot_shm(&screenshot);
        if (err == IDB_SUCCESS) {
            printf("Screenshot: %ux%u, %zu bytes, format: %s\n",
                   screenshot.width,
                   screenshot.height,
                   screenshot.size,
                   screenshot.format);
            printf("Shared memory key: %s\n", idb_shm_get_key(screenshot.handle));
            printf("Base address: %p\n", screenshot.base_address);
            
            // Verify data
            if (screenshot.base_address) {
                uint8_t* data = (uint8_t*)screenshot.base_address;
                uint32_t checksum = 0;
                for (size_t i = 0; i < screenshot.size; i += 1024) {
                    checksum ^= data[i];
                }
                printf("Data checksum: 0x%08X\n", checksum);
            }
            
            idb_free_screenshot_shm(&screenshot);
        } else {
            printf("Screenshot failed: %s\n", idb_error_string(err));
        }
        
        // Test 2: Screenshot streaming
        printf("\n--- Test 2: Screenshot Stream (5 seconds at 10 FPS) ---\n");
        err = idb_screenshot_stream_shm(screenshot_callback, NULL, 10);
        if (err == IDB_SUCCESS) {
            printf("Streaming started...\n");
            sleep(5);
            
            err = idb_screenshot_stream_stop();
            printf("Streaming stopped: %s\n", idb_error_string(err));
        } else {
            printf("Failed to start stream: %s\n", idb_error_string(err));
        }
        
        // Test 3: Memory pressure test
        printf("\n--- Test 3: Memory Pressure Test ---\n");
        printf("Taking 100 screenshots rapidly...\n");
        
        NSDate* start = [NSDate date];
        for (int i = 0; i < 100; i++) {
            idb_shm_screenshot_t shot = {0};
            err = idb_take_screenshot_shm(&shot);
            if (err == IDB_SUCCESS) {
                idb_free_screenshot_shm(&shot);
            } else {
                printf("Screenshot %d failed: %s\n", i, idb_error_string(err));
                break;
            }
        }
        NSTimeInterval elapsed = -[start timeIntervalSinceNow];
        printf("Completed in %.2f seconds (%.1f FPS)\n", elapsed, 100.0 / elapsed);
        
        // Cleanup
        printf("\n--- Cleanup ---\n");
        idb_disconnect_target();
        idb_shutdown();
        
        printf("\nTest completed successfully!\n");
        return 0;
    }
}