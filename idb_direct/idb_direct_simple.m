// Simplified idb_direct implementation for initial testing
#import <Foundation/Foundation.h>
#import "idb_direct.h"

// For now, just stub implementations to get the build working
idb_error_t idb_initialize(void) {
    NSLog(@"idb_direct: initialize called");
    return IDB_SUCCESS;
}

idb_error_t idb_shutdown(void) {
    NSLog(@"idb_direct: shutdown called");
    return IDB_SUCCESS;
}

idb_error_t idb_connect_target(const char* udid, idb_target_type_t type) {
    NSLog(@"idb_direct: connect_target called with UDID: %s", udid);
    return IDB_SUCCESS;
}

idb_error_t idb_disconnect_target(void) {
    NSLog(@"idb_direct: disconnect_target called");
    return IDB_SUCCESS;
}

idb_error_t idb_tap(double x, double y) {
    NSLog(@"idb_direct: tap called at (%.2f, %.2f)", x, y);
    // TODO: Implement actual tap using FBSimulatorHID
    return IDB_SUCCESS;
}

idb_error_t idb_touch_event(idb_touch_type_t type, double x, double y) {
    NSLog(@"idb_direct: touch_event called - type: %d, position: (%.2f, %.2f)", type, x, y);
    return IDB_SUCCESS;
}

idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds) {
    NSLog(@"idb_direct: swipe called from (%.2f, %.2f) to (%.2f, %.2f)", 
          from.x, from.y, to.x, to.y);
    return IDB_SUCCESS;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    NSLog(@"idb_direct: take_screenshot called");
    
    // For now, return a dummy 1x1 PNG
    unsigned char png_data[] = {
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  // IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,  // IDAT chunk
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0x0F, 0x00, 0x00,
        0x01, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,  // IEND chunk
        0xAE, 0x42, 0x60, 0x82
    };
    
    screenshot->size = sizeof(png_data);
    screenshot->data = (uint8_t*)malloc(screenshot->size);
    if (!screenshot->data) {
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    
    memcpy(screenshot->data, png_data, screenshot->size);
    screenshot->format = strdup("png");
    if (!screenshot->format) {
        free(screenshot->data);
        screenshot->data = NULL;
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    screenshot->width = 1;
    screenshot->height = 1;
    
    return IDB_SUCCESS;
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

const char* idb_error_string(idb_error_t error) {
    switch(error) {
        case IDB_SUCCESS: return "Success";
        case IDB_ERROR_NOT_INITIALIZED: return "Not initialized";
        case IDB_ERROR_INVALID_PARAMETER: return "Invalid parameter";
        case IDB_ERROR_DEVICE_NOT_FOUND: return "Device not found";
        case IDB_ERROR_SIMULATOR_NOT_RUNNING: return "Simulator not running";
        case IDB_ERROR_OPERATION_FAILED: return "Operation failed";
        case IDB_ERROR_TIMEOUT: return "Timeout";
        case IDB_ERROR_OUT_OF_MEMORY: return "Out of memory";
        default: return "Unknown error";
    }
}

const char* idb_version(void) {
    return "0.1.0-stub";
}