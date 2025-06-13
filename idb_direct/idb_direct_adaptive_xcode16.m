#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "idb_direct.h"

// We'll use runtime APIs to interact with SimulatorKit
static Class SimDeviceClass = nil;
static Class SimDeviceSetClass = nil;
static Class SimServiceContextClass = nil;

// Global state
static struct {
    id current_device;  // SimDevice instance
    _Atomic(BOOL) initialized;
    dispatch_queue_t sync_queue;
} g_idb_state = {0};

// Thread-safe synchronization macros
#define IDB_SYNC_INIT() \
    static dispatch_once_t once; \
    dispatch_once(&once, ^{ \
        g_idb_state.sync_queue = dispatch_queue_create("com.arkavo.idb_adaptive_sync", DISPATCH_QUEUE_SERIAL); \
    })

#define IDB_SYNCHRONIZED(block) \
    IDB_SYNC_INIT(); \
    dispatch_sync(g_idb_state.sync_queue, ^{ \
        @autoreleasepool { \
            block \
        } \
    })

// Export helper for shared memory implementation
id g_idb_state_current_device(void) {
    __block id device = nil;
    IDB_SYNCHRONIZED({
        device = g_idb_state.current_device;
    });
    return device;
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
    [7] = "Out of memory",
};

// Helper function to get the active device set with Xcode 16+ compatibility
static id FBIDBGetActiveDeviceSet(void) {
    @autoreleasepool {
        // Try Xcode <= 15 API first
        if ([SimDeviceSetClass respondsToSelector:@selector(defaultSet)]) {
            return [SimDeviceSetClass performSelector:@selector(defaultSet)];
        }
        
        // For Xcode 16+, use SimServiceContext
        if (SimServiceContextClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            SEL sharedContextSelector = @selector(sharedServiceContextForDeveloperDir:error:);
#pragma clang diagnostic pop
            if ([SimServiceContextClass respondsToSelector:sharedContextSelector]) {
                NSError *error = nil;
                NSString *developerDir = [NSProcessInfo.processInfo.environment objectForKey:@"DEVELOPER_DIR"];
                // Fallback to default Xcode location if DEVELOPER_DIR not set
                if (!developerDir) {
                    NSString *defaultPath = @"/Applications/Xcode.app/Contents/Developer";
                    if ([[NSFileManager defaultManager] fileExistsAtPath:defaultPath]) {
                        developerDir = defaultPath;
                    } else {
                        NSLog(@"[idb] Default Xcode path not found at %@, DEVELOPER_DIR not set", defaultPath);
                        return nil;
                    }
                }
                
                id sharedContext = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(SimServiceContextClass, sharedContextSelector, developerDir, &error);
                
                if (sharedContext) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
                    SEL defaultSetSelector = @selector(defaultDeviceSetWithError:);
#pragma clang diagnostic pop
                    if ([sharedContext respondsToSelector:defaultSetSelector]) {
                        error = nil;
                        id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(sharedContext, defaultSetSelector, &error);
                        if (deviceSet) {
                            return deviceSet;
                        }
                    }
                }
            }
        }
        
        NSLog(@"[idb] CoreSimulator API changed - could not obtain device set. Tried both SimDeviceSet.defaultSet and SimServiceContext.defaultDeviceSetWithError:");
        return nil;
    }
}

static BOOL load_simulator_kit(void) {
    static dispatch_once_t once;
    static BOOL loaded = NO;
    
    dispatch_once(&once, ^{
        // Load CoreSimulator framework
        void* handle = dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_LAZY);
        if (!handle) {
            NSLog(@"Failed to load CoreSimulator.framework");
            return;
        }
        
        SimDeviceClass = NSClassFromString(@"SimDevice");
        SimDeviceSetClass = NSClassFromString(@"SimDeviceSet");
        SimServiceContextClass = NSClassFromString(@"SimServiceContext");
        
        if (SimDeviceClass && SimDeviceSetClass) {
            NSLog(@"Successfully loaded CoreSimulator classes");
            loaded = YES;
        }
    });
    
    return loaded;
}

idb_error_t idb_initialize(void) {
    if (!load_simulator_kit()) {
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    IDB_SYNCHRONIZED({
        atomic_store(&g_idb_state.initialized, YES);
        NSLog(@"idb_direct: initialized successfully");
    });
    return IDB_SUCCESS;
}

idb_error_t idb_shutdown(void) {
    IDB_SYNCHRONIZED({
        if (g_idb_state.current_device) {
            g_idb_state.current_device = nil;
        }
        atomic_store(&g_idb_state.initialized, NO);
    });
    return IDB_SUCCESS;
}

idb_error_t idb_connect_target(const char* udid, idb_target_type_t type) {
    if (!atomic_load(&g_idb_state.initialized)) {
        return IDB_ERROR_NOT_INITIALIZED;
    }
    
    if (!udid || type != IDB_TARGET_SIMULATOR) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    IDB_SYNCHRONIZED({
        @autoreleasepool {
            NSString* targetUdid = [NSString stringWithUTF8String:udid];
            
            // Get default device set using compatibility helper
            id deviceSet = FBIDBGetActiveDeviceSet();
            
            if (!deviceSet) {
                NSLog(@"Failed to get default device set");
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Get all devices
            SEL devicesSelector = NSSelectorFromString(@"devices");
            NSArray* devices = [deviceSet performSelector:devicesSelector];
            
            // Find our target device
            for (id device in devices) {
                SEL udidSelector = NSSelectorFromString(@"UDID");
                NSUUID* deviceUDID = [device performSelector:udidSelector];
                
                if ([deviceUDID.UUIDString isEqualToString:targetUdid] || 
                    [targetUdid isEqualToString:@"booted"]) {
                    // Check if booted
                    SEL stateSelector = NSSelectorFromString(@"state");
                    NSInteger state = [[device performSelector:stateSelector] integerValue];
                    
                    if (state != 3) { // Booted state
                        NSLog(@"Simulator is not booted (state: %ld)", state);
                        result = IDB_ERROR_SIMULATOR_NOT_RUNNING;
                        return;
                    }
                    
                    g_idb_state.current_device = device;
                    NSLog(@"Connected to simulator: %@", deviceUDID.UUIDString);
                    return;
                }
            }
            
            NSLog(@"Simulator not found: %s", udid);
            result = IDB_ERROR_DEVICE_NOT_FOUND;
        }
    });
#pragma clang diagnostic pop
    
    return result;
}

idb_error_t idb_disconnect_target(void) {
    if (!atomic_load(&g_idb_state.initialized)) {
        return IDB_ERROR_NOT_INITIALIZED;
    }
    
    IDB_SYNCHRONIZED({
        g_idb_state.current_device = nil;
    });
    
    return IDB_SUCCESS;
}

// Minimal HID operations - these would need proper implementation
idb_error_t idb_tap(double x, double y) {
    if (!atomic_load(&g_idb_state.initialized)) {
        return IDB_ERROR_NOT_INITIALIZED;
    }
    
    __block idb_error_t result = IDB_ERROR_OPERATION_FAILED;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_device) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        // HID operations would go here
        // This would require using the SimDevice's HID interface
        NSLog(@"Tap at (%.1f, %.1f) - not implemented in adaptive version", x, y);
    });
    
    return result;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    if (!atomic_load(&g_idb_state.initialized)) {
        return IDB_ERROR_NOT_INITIALIZED;
    }
    
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Screenshot implementation would go here
    return IDB_ERROR_OPERATION_FAILED;
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
    return IDB_ERROR_OPERATION_FAILED;
}

idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds) {
    return IDB_ERROR_OPERATION_FAILED;
}

const char* idb_error_string(idb_error_t error) {
    int index = -error;
    if (index >= 0 && index < sizeof(g_error_strings)/sizeof(g_error_strings[0])) {
        return g_error_strings[index];
    }
    return "Unknown error";
}

const char* idb_version(void) {
    return "0.1.0-xcode16";
}