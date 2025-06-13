#ifndef IDB_DIRECT_H
#define IDB_DIRECT_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Error codes
typedef enum {
    IDB_SUCCESS = 0,
    IDB_ERROR_NOT_INITIALIZED = -1,
    IDB_ERROR_INVALID_PARAMETER = -2,
    IDB_ERROR_DEVICE_NOT_FOUND = -3,
    IDB_ERROR_SIMULATOR_NOT_RUNNING = -4,
    IDB_ERROR_OPERATION_FAILED = -5,
    IDB_ERROR_TIMEOUT = -6,
    IDB_ERROR_OUT_OF_MEMORY = -7,
    // Extended error codes
    IDB_ERROR_NOT_IMPLEMENTED = -100,
    IDB_ERROR_UNSUPPORTED = -101,
    IDB_ERROR_PERMISSION_DENIED = -102,
    IDB_ERROR_APP_NOT_FOUND = -103,
    IDB_ERROR_INVALID_APP_BUNDLE = -104,
} idb_error_t;

// Device types
typedef enum {
    IDB_TARGET_SIMULATOR = 0,
    IDB_TARGET_DEVICE = 1,
} idb_target_type_t;

// Touch event types
typedef enum {
    IDB_TOUCH_DOWN = 0,
    IDB_TOUCH_UP = 1,
    IDB_TOUCH_MOVE = 2,
} idb_touch_type_t;

// Structures
typedef struct {
    double x;
    double y;
} idb_point_t;

typedef struct {
    char* udid;
    char* name;
    char* os_version;
    char* device_type;
    idb_target_type_t type;
    bool is_running;
} idb_target_info_t;

typedef struct {
    uint8_t* data;
    size_t size;
    uint32_t width;
    uint32_t height;
    char* format; // "png", "jpeg", etc.
} idb_screenshot_t;

// Initialization and cleanup
idb_error_t idb_initialize(void);
idb_error_t idb_shutdown(void);

// Target management
idb_error_t idb_connect_target(const char* udid, idb_target_type_t type);
idb_error_t idb_disconnect_target(void);
idb_error_t idb_list_targets(idb_target_info_t** targets, size_t* count);
void idb_free_targets(idb_target_info_t* targets, size_t count);

// HID operations
idb_error_t idb_tap(double x, double y);
idb_error_t idb_touch_event(idb_touch_type_t type, double x, double y);
idb_error_t idb_swipe(idb_point_t from, idb_point_t to, double duration_seconds);

// Screenshot operations
idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot);
void idb_free_screenshot(idb_screenshot_t* screenshot);

// Utility
const char* idb_error_string(idb_error_t error);
const char* idb_version(void);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_H