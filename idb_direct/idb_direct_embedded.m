#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import <CompanionLib/CompanionLib.h>
#import <IDBCompanionUtilities/IDBCompanionUtilities-Swift.h>
#import "idb_direct_embedded.h"
#import "idb-Swift.h"

// Internal structure for companion handle
typedef struct idb_companion_handle {
    id<FBiOSTarget> target;
    FBIDBCommandExecutor* commandExecutor;
    FBIDBStorageManager* storageManager;
    FBTemporaryDirectory* temporaryDirectory;
    FBIDBLogger* logger;
    id<FBEventReporter> reporter;
    dispatch_queue_t queue;
    BOOL connected;
    idb_log_callback logCallback;
    void* logContext;
} idb_companion_handle_t;

// Internal structure for request handle
typedef struct idb_request_handle {
    idb_companion_handle_t* companion;
    NSString* method;
    NSMutableDictionary* parameters;
    NSMutableData* data;
} idb_request_handle_t;

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
    [8] = "Not supported"
};

// Default timeout for FBFuture operations (15 seconds)
static const NSTimeInterval kDefaultTimeout = 15.0;

// Helper function to await future with timeout
static id FBIDBWaitWithTimeout(FBFuture* future, NSTimeInterval timeout, NSError** error) {
    if (!future) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.arkavo.idb" code:-1 
                userInfo:@{NSLocalizedDescriptionKey: @"Future is nil"}];
        }
        return nil;
    }
    
    // Log the operation being waited on
    NSLog(@"[IDB] Waiting for future with timeout: %.1fs", timeout);
    
    id result = [future awaitWithTimeout:timeout error:error];
    
    if (!result && error && *error) {
        NSLog(@"[IDB] Future timed out or failed: %@", (*error).localizedDescription);
    }
    
    return result;
}

// Custom logger that forwards to callback
@interface IDBEmbeddedLogger : NSObject <FBControlCoreLogger>
@property (nonatomic, assign) idb_log_callback callback;
@property (nonatomic, assign) void* context;
@property (nonatomic, assign) int level;
@end

@implementation IDBEmbeddedLogger

- (id<FBControlCoreLogger>)info {
    return self;
}

- (id<FBControlCoreLogger>)debug {
    return self;
}

- (id<FBControlCoreLogger>)error {
    return self;
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue {
    return self;
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix {
    return self;
}

- (void)log:(NSString *)message {
    if (self.callback) {
        self.callback(message.UTF8String, self.level, self.context);
    }
}

- (void)logFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:message];
}

@end

// Helper macros
#define CHECK_HANDLE(handle) \
    if (!handle) { \
        return IDB_ERROR_INVALID_PARAMETER; \
    }

#define CHECK_CONNECTED(handle) \
    if (!handle->connected || !handle->target) { \
        return IDB_ERROR_DEVICE_NOT_FOUND; \
    }

// Implementation
idb_error_t idb_companion_create(idb_companion_handle_t** handle) {
    if (!handle) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    @autoreleasepool {
        idb_companion_handle_t* companion = calloc(1, sizeof(idb_companion_handle_t));
        if (!companion) {
            return IDB_ERROR_OUT_OF_MEMORY;
        }
        
        companion->queue = dispatch_queue_create("com.arkavo.idb_embedded", DISPATCH_QUEUE_SERIAL);
        
        // Create embedded logger
        IDBEmbeddedLogger* embeddedLogger = [[IDBEmbeddedLogger alloc] init];
        companion->logger = [FBIDBLogger loggerWithVerboseLogging:YES];
        
        // Use empty event reporter for embedded mode
        companion->reporter = [[EmptyEventReporter alloc] init];
        
        companion->temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:companion->logger];
        
        *handle = companion;
        return IDB_SUCCESS;
    }
}

idb_error_t idb_companion_destroy(idb_companion_handle_t* handle) {
    CHECK_HANDLE(handle);
    
    @autoreleasepool {
        if (handle->connected) {
            idb_companion_disconnect(handle);
        }
        
        [handle->temporaryDirectory cleanOnExit];
        
        if (handle->queue) {
            handle->queue = nil;
        }
        
        free(handle);
        return IDB_SUCCESS;
    }
}

idb_error_t idb_companion_connect(idb_companion_handle_t* handle, 
                                   const char* udid, 
                                   idb_target_type_t type) {
    CHECK_HANDLE(handle);
    
    if (!udid) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSString* udidString = [NSString stringWithUTF8String:udid];
            NSError* error = nil;
            
            // Get target sets based on type
            NSArray<id<FBiOSTargetSet>>* targetSets = nil;
            
            if (type == IDB_TARGET_SIMULATOR) {
                // Load simulator frameworks
                if (![FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworks:handle->logger error:&error]) {
                    result = IDB_ERROR_OPERATION_FAILED;
                    return;
                }
                
                FBSimulatorControlConfiguration* config = [FBSimulatorControlConfiguration 
                    configurationWithDeviceSetPath:nil 
                    logger:handle->logger 
                    reporter:handle->reporter];
                    
                FBSimulatorControl* control = [FBSimulatorControl withConfiguration:config error:&error];
                if (!control) {
                    result = IDB_ERROR_OPERATION_FAILED;
                    return;
                }
                
                targetSets = @[control.set];
                
                // Pre-flight check: Ensure simulators exist
                NSArray *allDevices = [control.set query:[FBiOSTargetQuery queryWithState:FBiOSTargetStateUnknown]];
                if (allDevices.count == 0) {
                    NSLog(@"[IDB] No simulators found. CoreSimulator may need initialization.");
                    NSLog(@"[IDB] Try running 'xcrun simctl list' to initialize CoreSimulator.");
                    result = IDB_ERROR_DEVICE_NOT_FOUND;
                    return;
                }
            } else if (type == IDB_TARGET_DEVICE) {
                // Load device frameworks
                if (![FBDeviceControlFrameworkLoader.new loadPrivateFrameworks:handle->logger error:&error]) {
                    result = IDB_ERROR_OPERATION_FAILED;
                    return;
                }
                
                FBDeviceSet* deviceSet = [FBDeviceSet setWithLogger:handle->logger delegate:nil ecidFilter:nil error:&error];
                if (!deviceSet) {
                    result = IDB_ERROR_OPERATION_FAILED;
                    return;
                }
                
                targetSets = @[deviceSet];
            }
            
            // Find target by UDID
            FBFuture<id<FBiOSTarget>>* targetFuture = [FBiOSTargetProvider 
                targetWithUDID:udidString 
                targetSets:targetSets 
                warmUp:YES 
                logger:handle->logger];
                
            id<FBiOSTarget> target = FBIDBWaitWithTimeout(targetFuture, kDefaultTimeout, &error);
            if (!target) {
                if (error && error.code == NSURLErrorTimedOut) {
                    NSLog(@"[IDB] Timeout while searching for target %@", udidString);
                    result = IDB_ERROR_TIMEOUT;
                } else {
                    NSLog(@"[IDB] Target not found: %@ (error: %@)", udidString, error);
                    result = IDB_ERROR_DEVICE_NOT_FOUND;
                }
                return;
            }
            
            // Create storage manager
            handle->storageManager = [FBIDBStorageManager managerForTarget:target logger:handle->logger error:&error];
            if (!handle->storageManager) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Create command executor
            handle->commandExecutor = [FBIDBCommandExecutor
                commandExecutorForTarget:target
                storageManager:handle->storageManager
                temporaryDirectory:handle->temporaryDirectory
                debugserverPort:0  // No debugserver port in embedded mode
                logger:handle->logger];
            
            handle->target = target;
            handle->connected = YES;
        }
    });
    
    return result;
}

idb_error_t idb_companion_disconnect(idb_companion_handle_t* handle) {
    CHECK_HANDLE(handle);
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            handle->target = nil;
            handle->commandExecutor = nil;
            handle->storageManager = nil;
            handle->connected = NO;
        }
    });
    
    return IDB_SUCCESS;
}

idb_error_t idb_companion_tap(idb_companion_handle_t* handle, double x, double y) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            
            // Create HID event for tap
            FBFuture* future = [[handle->commandExecutor hid] 
                tapAtX:x y:y];
            
            FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
            }
        }
    });
    
    return result;
}

idb_error_t idb_companion_swipe(idb_companion_handle_t* handle, 
                                 double from_x, double from_y,
                                 double to_x, double to_y,
                                 double duration_seconds) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            
            // Create HID event for swipe
            FBFuture* future = [[handle->commandExecutor hid] 
                swipeFromX:from_x 
                fromY:from_y 
                toX:to_x 
                toY:to_y 
                duration:duration_seconds];
            
            FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
            }
        }
    });
    
    return result;
}

idb_error_t idb_companion_screenshot(idb_companion_handle_t* handle,
                                      uint8_t** data, size_t* size,
                                      uint32_t* width, uint32_t* height) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    if (!data || !size) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            
            // Take screenshot
            FBFuture<NSData*>* future = [[handle->commandExecutor screenshot] 
                takeInFormat:FBScreenshotFormatPNG];
            
            NSData* imageData = FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (!imageData || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            // Allocate and copy data
            *size = imageData.length;
            *data = (uint8_t*)malloc(*size);
            if (!*data) {
                result = IDB_ERROR_OUT_OF_MEMORY;
                return;
            }
            
            memcpy(*data, imageData.bytes, *size);
            
            // TODO: Parse PNG to get dimensions
            if (width) *width = 0;
            if (height) *height = 0;
        }
    });
    
    return result;
}

void idb_companion_free_screenshot(uint8_t* data) {
    if (data) {
        free(data);
    }
}

idb_error_t idb_companion_launch_app(idb_companion_handle_t* handle, const char* bundle_id) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    if (!bundle_id) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            NSString* bundleIdString = [NSString stringWithUTF8String:bundle_id];
            
            FBApplicationLaunchConfiguration* config = [FBApplicationLaunchConfiguration 
                configurationWithBundleID:bundleIdString 
                bundleName:nil 
                arguments:@[] 
                environment:@{} 
                waitForDebugger:NO 
                output:FBProcessOutputConfiguration.defaultOutputToDevNull];
            
            FBFuture* future = [[handle->commandExecutor applicationCommands] 
                launchApplication:config];
            
            FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
            }
        }
    });
    
    return result;
}

idb_error_t idb_companion_terminate_app(idb_companion_handle_t* handle, const char* bundle_id) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    if (!bundle_id) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            NSString* bundleIdString = [NSString stringWithUTF8String:bundle_id];
            
            FBFuture* future = [[handle->commandExecutor applicationCommands] 
                terminateApplicationWithBundleID:bundleIdString];
            
            FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
            }
        }
    });
    
    return result;
}

idb_error_t idb_companion_list_apps(idb_companion_handle_t* handle, 
                                     char*** bundle_ids, size_t* count) {
    CHECK_HANDLE(handle);
    CHECK_CONNECTED(handle);
    
    if (!bundle_ids || !count) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    dispatch_sync(handle->queue, ^{
        @autoreleasepool {
            NSError* error = nil;
            
            FBFuture<NSArray<FBInstalledApplication*>*>* future = [[handle->commandExecutor applicationCommands] 
                installedApplications];
            
            NSArray<FBInstalledApplication*>* apps = FBIDBWaitWithTimeout(future, kDefaultTimeout, &error);
            if (!apps || error) {
                result = IDB_ERROR_OPERATION_FAILED;
                return;
            }
            
            *count = apps.count;
            *bundle_ids = (char**)calloc(*count, sizeof(char*));
            if (!*bundle_ids) {
                result = IDB_ERROR_OUT_OF_MEMORY;
                return;
            }
            
            for (NSUInteger i = 0; i < apps.count; i++) {
                const char* bundleId = apps[i].bundle.identifier.UTF8String;
                (*bundle_ids)[i] = strdup(bundleId);
                if (!(*bundle_ids)[i]) {
                    // Clean up previously allocated strings
                    for (NSUInteger j = 0; j < i; j++) {
                        free((*bundle_ids)[j]);
                    }
                    free(*bundle_ids);
                    *bundle_ids = NULL;
                    result = IDB_ERROR_OUT_OF_MEMORY;
                    return;
                }
            }
        }
    });
    
    return result;
}

void idb_companion_free_app_list(char** bundle_ids, size_t count) {
    if (bundle_ids) {
        for (size_t i = 0; i < count; i++) {
            if (bundle_ids[i]) {
                free(bundle_ids[i]);
            }
        }
        free(bundle_ids);
    }
}

idb_error_t idb_companion_set_log_callback(idb_companion_handle_t* handle,
                                            idb_log_callback callback,
                                            void* context) {
    CHECK_HANDLE(handle);
    
    handle->logCallback = callback;
    handle->logContext = context;
    
    // Update logger if it's an embedded logger
    if ([handle->logger isKindOfClass:[IDBEmbeddedLogger class]]) {
        IDBEmbeddedLogger* embeddedLogger = (IDBEmbeddedLogger*)handle->logger;
        embeddedLogger.callback = callback;
        embeddedLogger.context = context;
    }
    
    return IDB_SUCCESS;
}

const char* idb_companion_error_string(idb_error_t error) {
    int index = -error;
    if (index >= 0 && index < sizeof(g_error_strings) / sizeof(char*)) {
        return g_error_strings[index];
    }
    return "Unknown error";
}

const char* idb_companion_version(void) {
    return "1.0.0-embedded";
}