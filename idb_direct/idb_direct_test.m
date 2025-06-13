//
// idb_direct_test.m
// Simple smoke test for idb_direct static library
//

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "idb_direct.h"

static void print_result(const char* operation, idb_error_t result) {
    if (result == IDB_SUCCESS) {
        printf("✓ %s: SUCCESS\n", operation);
    } else {
        printf("✗ %s: FAILED - %s (code: %d)\n", operation, idb_error_string(result), result);
    }
}

static BOOL find_booted_simulator(char* udid_out, size_t udid_size) {
    // Use simctl to find a booted simulator
    FILE* fp = popen("xcrun simctl list devices booted -j", "r");
    if (!fp) {
        return NO;
    }
    
    char buffer[4096];
    NSMutableString* json = [NSMutableString string];
    while (fgets(buffer, sizeof(buffer), fp) != NULL) {
        [json appendString:[NSString stringWithUTF8String:buffer]];
    }
    pclose(fp);
    
    NSError* error = nil;
    NSData* jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* devices = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error || !devices) {
        printf("Failed to parse simctl output: %s\n", error.localizedDescription.UTF8String);
        return NO;
    }
    
    // Find first booted device
    for (NSString* runtime in devices[@"devices"]) {
        NSArray* deviceList = devices[@"devices"][runtime];
        for (NSDictionary* device in deviceList) {
            if ([device[@"state"] isEqualToString:@"Booted"]) {
                NSString* udid = device[@"udid"];
                strncpy(udid_out, udid.UTF8String, udid_size - 1);
                udid_out[udid_size - 1] = '\0';
                printf("Found booted simulator: %s (%s)\n", [device[@"name"] UTF8String], udid.UTF8String);
                return YES;
            }
        }
    }
    
    return NO;
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        printf("IDB Direct Static Library Smoke Test\n");
        printf("====================================\n\n");
        
        // Check for CI mode
        BOOL ci_mode = getenv("CI") != NULL || (argc > 1 && strcmp(argv[1], "--ci") == 0);
        if (ci_mode) {
            printf("Running in CI mode (limited tests)\n\n");
        }
        
        // Test 1: Version
        printf("Library version: %s\n\n", idb_version());
        
        // Test 2: Initialize
        printf("Testing initialization...\n");
        idb_error_t result = idb_initialize();
        print_result("idb_initialize", result);
        if (result != IDB_SUCCESS) {
            return 1;
        }
        
        // In CI mode, skip simulator tests
        if (ci_mode) {
            printf("\nCI mode: Skipping simulator-dependent tests\n");
            
            // Test error handling
            printf("\nTesting error handling...\n");
            result = idb_connect_target(NULL, IDB_TARGET_SIMULATOR);
            if (result == IDB_ERROR_INVALID_PARAMETER) {
                print_result("NULL parameter handling", IDB_SUCCESS);
            } else {
                print_result("NULL parameter handling", IDB_ERROR_OPERATION_FAILED);
            }
            
            result = idb_tap(100, 100);
            if (result == IDB_ERROR_DEVICE_NOT_FOUND) {
                print_result("No device tap handling", IDB_SUCCESS);
            } else {
                print_result("No device tap handling", IDB_ERROR_OPERATION_FAILED);
            }
            
            // Shutdown
            result = idb_shutdown();
            print_result("idb_shutdown", result);
            
            printf("\n✅ CI tests completed!\n");
            return 0;
        }
        
        // Test 3: Find booted simulator
        printf("\nFinding booted simulator...\n");
        char udid[128] = {0};
        if (!find_booted_simulator(udid, sizeof(udid))) {
            printf("No booted simulator found. Please boot a simulator and try again.\n");
            printf("Run: xcrun simctl boot <device_udid>\n");
            idb_shutdown();
            return 1;
        }
        
        // Test 4: Connect to simulator
        printf("\nConnecting to simulator...\n");
        result = idb_connect_target(udid, IDB_TARGET_SIMULATOR);
        print_result("idb_connect_target", result);
        if (result != IDB_SUCCESS) {
            idb_shutdown();
            return 1;
        }
        
        // Test 5: Tap test
        printf("\nTesting tap at center of screen...\n");
        result = idb_tap(200, 400);
        print_result("idb_tap", result);
        
        // Test 6: Touch events
        printf("\nTesting touch events...\n");
        result = idb_touch_event(IDB_TOUCH_DOWN, 100, 100);
        print_result("idb_touch_event (down)", result);
        
        usleep(50000); // 50ms
        
        result = idb_touch_event(IDB_TOUCH_UP, 100, 100);
        print_result("idb_touch_event (up)", result);
        
        // Test 7: Swipe test
        printf("\nTesting swipe...\n");
        idb_point_t from = {100, 300};
        idb_point_t to = {300, 300};
        result = idb_swipe(from, to, 0.5);
        print_result("idb_swipe", result);
        
        // Test 8: Screenshot test
        printf("\nTesting screenshot...\n");
        idb_screenshot_t screenshot = {0};
        result = idb_take_screenshot(&screenshot);
        print_result("idb_take_screenshot", result);
        
        if (result == IDB_SUCCESS) {
            printf("  Screenshot captured: %zu bytes, format: %s\n", 
                   screenshot.size, screenshot.format);
            if (screenshot.width > 0 && screenshot.height > 0) {
                printf("  Dimensions: %dx%d\n", screenshot.width, screenshot.height);
            }
            
            // Optionally save to file
            if (argc > 1 && strcmp(argv[1], "--save-screenshot") == 0) {
                FILE* fp = fopen("test_screenshot.png", "wb");
                if (fp) {
                    fwrite(screenshot.data, 1, screenshot.size, fp);
                    fclose(fp);
                    printf("  Screenshot saved to test_screenshot.png\n");
                }
            }
            
            idb_free_screenshot(&screenshot);
        }
        
        // Test 9: Disconnect
        printf("\nDisconnecting...\n");
        result = idb_disconnect_target();
        print_result("idb_disconnect_target", result);
        
        // Test 10: Shutdown
        printf("\nShutting down...\n");
        result = idb_shutdown();
        print_result("idb_shutdown", result);
        
        printf("\n✅ All tests completed!\n");
        return 0;
    }
}