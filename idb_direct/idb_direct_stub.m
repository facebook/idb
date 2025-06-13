#import <Foundation/Foundation.h>
#import "idb_direct.h"

// Simple stub implementation for building the static library

// Error strings
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

idb_error_t idb_initialize(void) {
    NSLog(@"idb_direct: initialize stub");
    return IDB_SUCCESS;
}

idb_error_t idb_shutdown(void) {
    NSLog(@"idb_direct: shutdown stub");
    return IDB_SUCCESS;
}

idb_error_t idb_connect_target(const char* udid, idb_target_type_t type) {
    NSLog(@"idb_direct: connect_target stub - udid: %s, type: %d", udid, type);
    return IDB_SUCCESS;
}

idb_error_t idb_disconnect_target(void) {
    NSLog(@"idb_direct: disconnect_target stub");
    return IDB_SUCCESS;
}

idb_error_t idb_tap(double x, double y) {
    NSLog(@"idb_direct: tap stub - x: %f, y: %f", x, y);
    return IDB_SUCCESS;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    NSLog(@"idb_direct: take_screenshot stub");
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Return a dummy screenshot
    screenshot->width = 100;
    screenshot->height = 100;
    screenshot->size = 1024;
    screenshot->data = (uint8_t*)malloc(screenshot->size);
    if (!screenshot->data) {
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    memset(screenshot->data, 0, screenshot->size);
    screenshot->format = strdup("png");
    if (!screenshot->format) {
        free(screenshot->data);
        screenshot->data = NULL;
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    
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

idb_error_t idb_touch_event(idb_touch_type_t type, double x, double y) {
    NSLog(@"idb_direct: touch_event stub - type: %d, x: %f, y: %f", type, x, y);
    return IDB_SUCCESS;
}

idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds) {
    NSLog(@"idb_direct: swipe stub - from: (%f,%f) to: (%f,%f) duration: %f", 
          from.x, from.y, to.x, to.y, duration_seconds);
    return IDB_SUCCESS;
}

const char* idb_error_string(idb_error_t error) {
    int index = -error;
    if (index >= 0 && index < sizeof(g_error_strings)/sizeof(g_error_strings[0])) {
        return g_error_strings[index];
    }
    return "Unknown error";
}

const char* idb_version(void) {
    return "0.1.0-stub";
}