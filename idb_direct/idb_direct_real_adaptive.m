#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "idb_direct.h"

// We'll use runtime APIs to interact with SimulatorKit
static Class SimDeviceClass = nil;
static Class SimDeviceSetClass = nil;

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
            
            // Get default device set
            SEL defaultSetSelector = NSSelectorFromString(@"defaultSet");
            id deviceSet = [SimDeviceSetClass performSelector:defaultSetSelector];
            
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
                    result = IDB_SUCCESS;
                    return;
                }
            }
            
            result = IDB_ERROR_DEVICE_NOT_FOUND;
        }
    });
#pragma clang diagnostic pop
    
    return result;
}

idb_error_t idb_disconnect_target(void) {
    IDB_SYNCHRONIZED({
        g_idb_state.current_device = nil;
    });
    return IDB_SUCCESS;
}

// Forward declaration
static idb_error_t idb_mouse_event(double x, double y, BOOL down);

idb_error_t idb_tap(double x, double y) {
    // Use simple mouse event API that's more stable across versions
    return idb_mouse_event(x, y, YES) == IDB_SUCCESS && 
           idb_mouse_event(x, y, NO) == IDB_SUCCESS ? IDB_SUCCESS : IDB_ERROR_OPERATION_FAILED;
}

// Simplified mouse event that works across Xcode versions
static idb_error_t idb_mouse_event(double x, double y, BOOL down) {
    __block id current_device = nil;
    IDB_SYNCHRONIZED({
        current_device = g_idb_state.current_device;
    });
    
    if (!current_device) {
        return IDB_ERROR_DEVICE_NOT_FOUND;
    }
    
    @autoreleasepool {
        NSError* error = nil;
        
        // Try multiple approaches to send events
        
        // Approach 1: Try postMouseEvent selector (older API)
        SEL mouseEventSelector = NSSelectorFromString(@"postMouseEventWithType:x:y:");
        if ([current_device respondsToSelector:mouseEventSelector]) {
            NSMethodSignature* sig = [current_device methodSignatureForSelector:mouseEventSelector];
            NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:current_device];
            [inv setSelector:mouseEventSelector];
            
            int eventType = down ? 1 : 2; // 1=down, 2=up
            [inv setArgument:&eventType atIndex:2];
            [inv setArgument:&x atIndex:3];
            [inv setArgument:&y atIndex:4];
            [inv invoke];
            
            NSLog(@"Sent mouse event via postMouseEvent");
            return IDB_SUCCESS;
        }
        
        // Approach 2: Try sendEventWithType (newer API)
        SEL sendEventSelector = NSSelectorFromString(@"sendEventWithType:path:error:");
        if ([current_device respondsToSelector:sendEventSelector]) {
            NSMethodSignature* sig = [current_device methodSignatureForSelector:sendEventSelector];
            NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:current_device];
            [inv setSelector:sendEventSelector];
            
            NSString* eventType = @"touch";
            NSArray* path = @[@{
                @"x": @(x),
                @"y": @(y),
                @"type": down ? @"down" : @"up"
            }];
            
            [inv setArgument:&eventType atIndex:2];
            [inv setArgument:&path atIndex:3];
            [inv setArgument:&error atIndex:4];
            [inv invoke];
            
            BOOL result = NO;
            [inv getReturnValue:&result];
            
            if (result) {
                NSLog(@"Sent touch event via sendEventWithType");
                return IDB_SUCCESS;
            }
        }
        
        // Approach 3: Try HID interface
        SEL hidSelector = NSSelectorFromString(@"hid");
        if ([current_device respondsToSelector:hidSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id hid = [current_device performSelector:hidSelector];
#pragma clang diagnostic pop
            if (hid) {
                // Try various HID methods
                SEL tapSelector = NSSelectorFromString(@"tapAtX:y:");
                if ([hid respondsToSelector:tapSelector]) {
                    NSMethodSignature* sig = [hid methodSignatureForSelector:tapSelector];
                    NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:hid];
                    [inv setSelector:tapSelector];
                    [inv setArgument:&x atIndex:2];
                    [inv setArgument:&y atIndex:3];
                    [inv invoke];
                    
                    NSLog(@"Sent tap via HID interface");
                    return IDB_SUCCESS;
                }
            }
        }
        
        NSLog(@"No compatible touch API found");
        return IDB_ERROR_UNSUPPORTED;
    }
}

idb_error_t idb_touch_event(idb_touch_type_t type, double x, double y) {
    return idb_mouse_event(x, y, type == IDB_TOUCH_DOWN);
}

idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds) {
    NSLog(@"idb_direct: swipe not implemented");
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block id current_device = nil;
    IDB_SYNCHRONIZED({
        current_device = g_idb_state.current_device;
    });
    
    if (!current_device) {
        return IDB_ERROR_DEVICE_NOT_FOUND;
    }
    
    @autoreleasepool {
        NSError* error = nil;
        
        // Try different screenshot methods
        SEL screenshotSelector = NSSelectorFromString(@"screenshotWithError:");
        SEL screenshotSelectorNoError = NSSelectorFromString(@"screenshot");
        
        NSData* imageData = nil;
        
        if ([current_device respondsToSelector:screenshotSelector]) {
            NSMethodSignature* sig = [current_device methodSignatureForSelector:screenshotSelector];
            NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:current_device];
            [inv setSelector:screenshotSelector];
            [inv setArgument:&error atIndex:2];
            [inv invoke];
            [inv getReturnValue:&imageData];
        } else if ([current_device respondsToSelector:screenshotSelectorNoError]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            imageData = [current_device performSelector:screenshotSelectorNoError];
#pragma clang diagnostic pop
        }
        
        if (!imageData) {
            NSLog(@"Screenshot failed: %@", error);
            return IDB_ERROR_OPERATION_FAILED;
        }
        
        screenshot->data = malloc(imageData.length);
        if (!screenshot->data) {
            return IDB_ERROR_OUT_OF_MEMORY;
        }
        
        memcpy(screenshot->data, imageData.bytes, imageData.length);
        screenshot->size = imageData.length;
        screenshot->format = strdup("png");
        if (!screenshot->format) {
            free(screenshot->data);
            screenshot->data = NULL;
            return IDB_ERROR_OUT_OF_MEMORY;
        }
        
        // We don't have width/height without decoding the PNG
        screenshot->width = 0;
        screenshot->height = 0;
        
        return IDB_SUCCESS;
    }
}

void idb_free_screenshot(idb_screenshot_t* screenshot) {
    if (screenshot) {
        free(screenshot->data);
        free(screenshot->format);
        screenshot->data = NULL;
        screenshot->format = NULL;
        screenshot->size = 0;
        screenshot->width = 0;
        screenshot->height = 0;
    }
}

const char* idb_error_string(idb_error_t error) {
    int index = -error;
    if (index >= 0 && index < sizeof(g_error_strings)/sizeof(g_error_strings[0])) {
        return g_error_strings[index];
    }
    
    // Handle extended error codes
    switch (error) {
        case IDB_ERROR_NOT_IMPLEMENTED:
            return "Not implemented";
        case IDB_ERROR_UNSUPPORTED:
            return "Unsupported";
        case IDB_ERROR_PERMISSION_DENIED:
            return "Permission denied";
        case IDB_ERROR_APP_NOT_FOUND:
            return "App not found";
        case IDB_ERROR_INVALID_APP_BUNDLE:
            return "Invalid app bundle";
        default:
            return "Unknown error";
    }
}

const char* idb_version(void) {
    return "0.1.0-adaptive";
}