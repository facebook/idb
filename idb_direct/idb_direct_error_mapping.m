#import "idb_direct_error_mapping.h"
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

// Comprehensive error string mapping
static const char* g_detailed_error_strings[] = {
    [0] = "Success",                                    // IDB_SUCCESS
    [1] = "Not initialized",                           // IDB_ERROR_NOT_INITIALIZED
    [2] = "Invalid parameter",                         // IDB_ERROR_INVALID_PARAMETER
    [3] = "Device not found",                          // IDB_ERROR_DEVICE_NOT_FOUND
    [4] = "Simulator not running",                     // IDB_ERROR_SIMULATOR_NOT_RUNNING
    [5] = "Operation failed",                          // IDB_ERROR_OPERATION_FAILED
    [6] = "Timeout",                                   // IDB_ERROR_TIMEOUT
    [7] = "Out of memory",                             // IDB_ERROR_OUT_OF_MEMORY
    // Extended error codes (offset by 100)
    [100] = "Not implemented",                         // IDB_ERROR_NOT_IMPLEMENTED
    [101] = "Unsupported",                            // IDB_ERROR_UNSUPPORTED
    [102] = "Permission denied",                       // IDB_ERROR_PERMISSION_DENIED
    [103] = "App not found",                          // IDB_ERROR_APP_NOT_FOUND
    [104] = "Invalid app bundle",                     // IDB_ERROR_INVALID_APP_BUNDLE
};

idb_error_t idb_map_nserror_to_idb_error(NSError* error) {
    if (!error) {
        return IDB_SUCCESS;
    }
    
    // Map by error domain first
    NSString* domain = error.domain;
    NSInteger code = error.code;
    
    // FBControlCore errors (use generic mapping since constants aren't public)
    if ([domain isEqualToString:FBControlCoreErrorDomain]) {
        // Common error code patterns
        if (code == -1) return IDB_ERROR_INVALID_PARAMETER;
        if (code == -2) return IDB_ERROR_TIMEOUT;
        if (code == -3) return IDB_ERROR_OUT_OF_MEMORY;
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // FBSimulatorControl errors  
    if ([domain containsString:@"FBSimulator"] || [domain containsString:@"simulator"]) {
        if (code == -1) return IDB_ERROR_SIMULATOR_NOT_RUNNING;
        if (code == -2) return IDB_ERROR_INVALID_PARAMETER;
        if (code == -3) return IDB_ERROR_TIMEOUT;
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // FBDeviceControl errors
    if ([domain containsString:@"FBDevice"] || [domain containsString:@"device"]) {
        if (code == -1) return IDB_ERROR_DEVICE_NOT_FOUND;
        if (code == -2) return IDB_ERROR_INVALID_PARAMETER;
        if (code == -3) return IDB_ERROR_TIMEOUT;
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Foundation/system errors
    if ([domain isEqualToString:NSPOSIXErrorDomain]) {
        switch (code) {
            case ENOENT:    // No such file or directory
            case ENOTDIR:   // Not a directory
                return IDB_ERROR_DEVICE_NOT_FOUND;
            case EACCES:    // Permission denied
            case EPERM:     // Operation not permitted
                return IDB_ERROR_PERMISSION_DENIED;
            case ENOMEM:    // Cannot allocate memory
                return IDB_ERROR_OUT_OF_MEMORY;
            case ETIMEDOUT: // Connection timed out
                return IDB_ERROR_TIMEOUT;
            case EINVAL:    // Invalid argument
                return IDB_ERROR_INVALID_PARAMETER;
            default:
                return IDB_ERROR_OPERATION_FAILED;
        }
    }
    
    if ([domain isEqualToString:NSCocoaErrorDomain]) {
        switch (code) {
            case NSFileNoSuchFileError:
            case NSFileReadNoSuchFileError:
                return IDB_ERROR_DEVICE_NOT_FOUND;
            case NSFileReadNoPermissionError:
            case NSFileWriteNoPermissionError:
                return IDB_ERROR_PERMISSION_DENIED;
            case NSKeyValueValidationError:
                return IDB_ERROR_INVALID_PARAMETER;
            default:
                return IDB_ERROR_OPERATION_FAILED;
        }
    }
    
    // IDB-specific errors
    if ([domain isEqualToString:@"com.facebook.idb"]) {
        // Map specific IDB error codes if needed
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Generic mapping for unknown domains
    if (code == -1) {
        return IDB_ERROR_OPERATION_FAILED;
    }
    if (code == -2) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    if (code == -3) {
        return IDB_ERROR_DEVICE_NOT_FOUND;
    }
    
    // Default fallback
    return IDB_ERROR_OPERATION_FAILED;
}

const char* idb_detailed_error_string(idb_error_t error) {
    int index = -error;
    
    // Handle positive error codes (shouldn't happen, but be safe)
    if (error >= 0) {
        return "Success";
    }
    
    // Handle core error codes (1-99)
    if (index >= 1 && index <= 7) {
        return g_detailed_error_strings[index];
    }
    
    // Handle extended error codes (100+)
    if (index >= 100 && index <= 104) {
        return g_detailed_error_strings[index];
    }
    
    // Unknown error code
    return "Unknown error";
}

BOOL idb_validate_error_mapping(void) {
    // Test that all defined error codes have mappings
    idb_error_t test_errors[] = {
        IDB_SUCCESS,
        IDB_ERROR_NOT_INITIALIZED,
        IDB_ERROR_INVALID_PARAMETER,
        IDB_ERROR_DEVICE_NOT_FOUND,
        IDB_ERROR_SIMULATOR_NOT_RUNNING,
        IDB_ERROR_OPERATION_FAILED,
        IDB_ERROR_TIMEOUT,
        IDB_ERROR_OUT_OF_MEMORY,
        IDB_ERROR_NOT_IMPLEMENTED,
        IDB_ERROR_UNSUPPORTED,
        IDB_ERROR_PERMISSION_DENIED,
        IDB_ERROR_APP_NOT_FOUND,
        IDB_ERROR_INVALID_APP_BUNDLE,
    };
    
    size_t num_errors = sizeof(test_errors) / sizeof(test_errors[0]);
    
    for (size_t i = 0; i < num_errors; i++) {
        const char* error_string = idb_detailed_error_string(test_errors[i]);
        if (strcmp(error_string, "Unknown error") == 0 && test_errors[i] != IDB_SUCCESS) {
            NSLog(@"Error mapping validation failed for error code: %d", test_errors[i]);
            return NO;
        }
    }
    
    // Test some common NSError scenarios
    NSArray* test_nserrors = @[
        [NSError errorWithDomain:FBControlCoreErrorDomain code:-1 userInfo:nil],
        [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil],
        [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil],
        [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil],
    ];
    
    size_t num_nserrors = test_nserrors.count;
    
    for (size_t i = 0; i < num_nserrors; i++) {
        idb_error_t mapped = idb_map_nserror_to_idb_error(test_nserrors[i]);
        if (mapped == IDB_SUCCESS) {
            NSLog(@"Error mapping validation failed: NSError mapped to success when it shouldn't");
            return NO;
        }
    }
    
    return YES;
}