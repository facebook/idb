#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBFuture.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorHID.h>
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import <stdatomic.h>
#import "idb_direct.h"

// Global state (thread-safe)
static struct {
    dispatch_queue_t queue;
    id<FBiOSTarget> current_target;
    FBSimulatorControl* simulator_control;
    FBDeviceControl* device_control;
    NSMutableDictionary* error_messages;
    _Atomic(BOOL) initialized;
} g_idb_state = {0};

// Macro for thread-safe operations
#define IDB_SYNCHRONIZED(block) \
    dispatch_sync(g_idb_state.queue, ^{ \
        @autoreleasepool { \
            block \
        } \
    })

#define IDB_CHECK_INITIALIZED() \
    if (!atomic_load(&g_idb_state.initialized)) { \
        return IDB_ERROR_NOT_INITIALIZED; \
    }

// Error string storage
static const char* g_error_strings[] = {
    [0] = "Success",
    [1] = "Not initialized",
    [2] = "Invalid parameter",
    [3] = "Device not found",
    [4] = "Simulator not running", 
    [5] = "Operation failed",
    [6] = "Timeout",
    [7] = "Out of memory"
};

// Implementation
idb_error_t idb_initialize(void) {
    __block idb_error_t result = IDB_SUCCESS;
    
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_idb_state.queue = dispatch_queue_create("org.arkavo.idb_direct", DISPATCH_QUEUE_SERIAL);
        g_idb_state.error_messages = [NSMutableDictionary dictionary];
        
        IDB_SYNCHRONIZED({
            NSError* error = nil;
            
            // Get default configuration
            FBSimulatorControlConfiguration* config = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:nil 
                                                                                                                options:FBSimulatorManagementOptionsDeleteAllOnFirstStart];
            
            // Initialize simulator control
            g_idb_state.simulator_control = [config startWithError:&error];
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
                g_idb_state.error_messages[@(result)] = error.localizedDescription;
                return;
            }
            
            // Initialize device control (optional, may fail on non-Mac)
            if ([FBDeviceControl class]) {
                g_idb_state.device_control = [FBDeviceControl.defaultControl startWithError:nil];
            }
            
            atomic_store(&g_idb_state.initialized, YES);
        });
    });
    
    return result;
}

idb_error_t idb_shutdown(void) {
    IDB_CHECK_INITIALIZED();
    
    IDB_SYNCHRONIZED({
        if (g_idb_state.current_target) {
            g_idb_state.current_target = nil;
        }
        
        g_idb_state.simulator_control = nil;
        g_idb_state.device_control = nil;
        atomic_store(&g_idb_state.initialized, NO);
    });
    
    return IDB_SUCCESS;
}

idb_error_t idb_connect_target(const char* udid, idb_target_type_t type) {
    IDB_CHECK_INITIALIZED();
    
    if (!udid) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        NSString* udidString = [NSString stringWithUTF8String:udid];
        NSError* error = nil;
        
        if (type == IDB_TARGET_SIMULATOR) {
            // Find simulator
            FBSimulator* simulator = [g_idb_state.simulator_control.set simulatorWithUDID:udidString];
            if (!simulator) {
                result = IDB_ERROR_DEVICE_NOT_FOUND;
                return;
            }
            
            // Boot if needed
            if (simulator.state != FBiOSTargetStateBooted) {
                if (![simulator bootWithError:&error]) {
                    result = IDB_ERROR_OPERATION_FAILED;
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                    return;
                }
            }
            
            g_idb_state.current_target = simulator;
        } else {
            // Device support
            if (!g_idb_state.device_control) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Find device
            NSArray<FBDevice*>* devices = [g_idb_state.device_control.devices filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"udid == %@", udidString]];
            
            if (devices.count == 0) {
                result = IDB_ERROR_DEVICE_NOT_FOUND;
                return;
            }
            
            g_idb_state.current_target = devices.firstObject;
        }
    });
    
    return result;
}

idb_error_t idb_disconnect_target(void) {
    IDB_CHECK_INITIALIZED();
    
    IDB_SYNCHRONIZED({
        g_idb_state.current_target = nil;
    });
    
    return IDB_SUCCESS;
}

idb_error_t idb_tap(double x, double y) {
    IDB_CHECK_INITIALIZED();
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        // For simulators, use HID interface
        if ([g_idb_state.current_target isKindOfClass:[FBSimulator class]]) {
            FBSimulator* simulator = (FBSimulator*)g_idb_state.current_target;
            
            // Get HID for simulator
            FBFuture<FBSimulatorHID *>* hidFuture = [FBSimulatorHID hidForSimulator:simulator];
            FBSimulatorHID* hid = [hidFuture await:&error];
            if (!hid || error) {
                NSLog(@"Failed to get HID: %@", error);
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Ensure HID is connected
            FBFuture<NSNull *>* connectFuture = [hid connect];
            id connectResult = [connectFuture await:&error];
            if (error) {
                NSLog(@"Failed to connect HID: %@", error);
                // Continue anyway, it might already be connected
            }
            
            // Send tap using the async API
            FBFuture<NSNull *>* downFuture = [hid sendTouchWithType:FBSimulatorHIDDirectionDown x:x y:y];
            id downResult = [downFuture await:&error];
            if (!downResult || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                if (error) {
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                }
                return;
            }
            
            // Small delay between down and up
            [NSThread sleepForTimeInterval:0.05];
            
            FBFuture<NSNull *>* upFuture = [hid sendTouchWithType:FBSimulatorHIDDirectionUp x:x y:y];
            id upResult = [upFuture await:&error];
            if (!upResult || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                if (error) {
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                }
            }
        } else {
            // Device tap would go here
            result = IDB_ERROR_OPERATION_FAILED;
        }
    });
    
    return result;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    IDB_CHECK_INITIALIZED();
    
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        // Take screenshot
        NSData* imageData = [g_idb_state.current_target takeScreenshot:FBScreenshotFormatPNG error:&error];
        if (error || !imageData) {
            result = IDB_ERROR_OPERATION_FAILED;
            if (error) {
                g_idb_state.error_messages[@(result)] = error.localizedDescription;
            }
            return;
        }
        
        // Copy to C buffer
        screenshot->size = imageData.length;
        screenshot->data = (uint8_t*)malloc(screenshot->size);
        if (!screenshot->data) {
            result = IDB_ERROR_OUT_OF_MEMORY;
            return;
        }
        
        memcpy(screenshot->data, imageData.bytes, screenshot->size);
        screenshot->format = strdup("png");
        if (!screenshot->format) {
            free(screenshot->data);
            screenshot->data = NULL;
            result = IDB_ERROR_OUT_OF_MEMORY;
            return;
        }
        
        // Get dimensions (simplified - would need proper PNG parsing)
        screenshot->width = 0;
        screenshot->height = 0;
    });
    
    return result;
}

void idb_free_screenshot(idb_screenshot_t* screenshot) {
    if (screenshot) {
        if (screenshot->data) {
            free(screenshot->data);
            screenshot->data = NULL;
        }
        if (screenshot->format) {
            free(screenshot->format);
            screenshot->format = NULL;
        }
        screenshot->size = 0;
        screenshot->width = 0;
        screenshot->height = 0;
    }
}

idb_error_t idb_touch_event(idb_touch_type_t type, double x, double y) {
    IDB_CHECK_INITIALIZED();
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        if ([g_idb_state.current_target isKindOfClass:[FBSimulator class]]) {
            FBSimulator* simulator = (FBSimulator*)g_idb_state.current_target;
            
            // Get HID for simulator
            FBFuture<FBSimulatorHID *>* hidFuture = [FBSimulatorHID hidForSimulator:simulator];
            FBSimulatorHID* hid = [hidFuture await:&error];
            if (!hid || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            FBSimulatorHIDDirection direction;
            switch (type) {
                case IDB_TOUCH_DOWN:
                    direction = FBSimulatorHIDDirectionDown;
                    break;
                case IDB_TOUCH_UP:
                    direction = FBSimulatorHIDDirectionUp;
                    break;
                case IDB_TOUCH_MOVE:
                    // For move, we'll use down direction as a placeholder
                    // Real implementation would track touch state
                    direction = FBSimulatorHIDDirectionDown;
                    break;
            }
            
            FBFuture<NSNull *>* future = [hid sendTouchWithType:direction x:x y:y];
            id futureResult = [future await:&error];
            if (!futureResult || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                if (error) {
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                }
            }
        } else {
            result = IDB_ERROR_OPERATION_FAILED;
        }
    });
    
    return result;
}

idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds) {
    IDB_CHECK_INITIALIZED();
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        if ([g_idb_state.current_target isKindOfClass:[FBSimulator class]]) {
            FBSimulator* simulator = (FBSimulator*)g_idb_state.current_target;
            
            // Get HID for simulator
            FBFuture<FBSimulatorHID *>* hidFuture = [FBSimulatorHID hidForSimulator:simulator];
            FBSimulatorHID* hid = [hidFuture await:&error];
            if (!hid || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Implement swipe as a series of touch events
            // Touch down at start point
            FBFuture<NSNull *>* downFuture = [hid sendTouchWithType:FBSimulatorHIDDirectionDown x:from.x y:from.y];
            id downResult = [downFuture await:&error];
            if (!downResult || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                if (error) {
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                }
                return;
            }
            
            // Interpolate points for smooth swipe
            int steps = (int)(duration_seconds * 60); // 60 FPS
            if (steps < 2) steps = 2;
            
            for (int i = 1; i < steps; i++) {
                double t = (double)i / (double)(steps - 1);
                double x = from.x + (to.x - from.x) * t;
                double y = from.y + (to.y - from.y) * t;
                
                // For move events, we might need to use a different approach
                // For now, just sleep between positions
                [NSThread sleepForTimeInterval:duration_seconds / steps];
            }
            
            // Touch up at end point
            FBFuture<NSNull *>* upFuture = [hid sendTouchWithType:FBSimulatorHIDDirectionUp x:to.x y:to.y];
            id upResult = [upFuture await:&error];
            if (!upResult || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                if (error) {
                    g_idb_state.error_messages[@(result)] = error.localizedDescription;
                }
            }
        } else {
            result = IDB_ERROR_OPERATION_FAILED;
        }
    });
    
    return result;
}

const char* idb_error_string(idb_error_t error) {
    int index = -error;
    if (index >= 0 && index < sizeof(g_error_strings)/sizeof(g_error_strings[0])) {
        return g_error_strings[index];
    }
    return "Unknown error";
}

const char* idb_version(void) {
    return "0.1.0";
}