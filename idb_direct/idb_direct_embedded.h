#ifndef IDB_DIRECT_EMBEDDED_H
#define IDB_DIRECT_EMBEDDED_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations for opaque types
typedef struct idb_companion_handle idb_companion_handle_t;
typedef struct idb_request_handle idb_request_handle_t;

// Error codes (same as idb_direct.h)
typedef enum {
    IDB_SUCCESS = 0,
    IDB_ERROR_NOT_INITIALIZED = -1,
    IDB_ERROR_INVALID_PARAMETER = -2,
    IDB_ERROR_DEVICE_NOT_FOUND = -3,
    IDB_ERROR_SIMULATOR_NOT_RUNNING = -4,
    IDB_ERROR_OPERATION_FAILED = -5,
    IDB_ERROR_TIMEOUT = -6,
    IDB_ERROR_OUT_OF_MEMORY = -7,
    IDB_ERROR_NOT_SUPPORTED = -8,
} idb_error_t;

// Device types (same as idb_direct.h)
typedef enum {
    IDB_TARGET_SIMULATOR = 0,
    IDB_TARGET_DEVICE = 1,
} idb_target_type_t;

// Callback types for async operations
typedef void (*idb_completion_callback)(idb_error_t error, const void* result, void* context);
typedef void (*idb_data_callback)(const uint8_t* data, size_t size, void* context);
typedef void (*idb_log_callback)(const char* message, int level, void* context);

// Companion lifecycle management
idb_error_t idb_companion_create(idb_companion_handle_t** handle);
idb_error_t idb_companion_destroy(idb_companion_handle_t* handle);

// Target connection
idb_error_t idb_companion_connect(idb_companion_handle_t* handle, 
                                  const char* udid, 
                                  idb_target_type_t type);
idb_error_t idb_companion_disconnect(idb_companion_handle_t* handle);

// Direct method invocation (synchronous)
idb_error_t idb_companion_tap(idb_companion_handle_t* handle, double x, double y);
idb_error_t idb_companion_swipe(idb_companion_handle_t* handle, 
                                double from_x, double from_y,
                                double to_x, double to_y,
                                double duration_seconds);

// Screenshot (synchronous)
idb_error_t idb_companion_screenshot(idb_companion_handle_t* handle,
                                     uint8_t** data, size_t* size,
                                     uint32_t* width, uint32_t* height);
void idb_companion_free_screenshot(uint8_t* data);

// App operations (synchronous)
idb_error_t idb_companion_launch_app(idb_companion_handle_t* handle, const char* bundle_id);
idb_error_t idb_companion_terminate_app(idb_companion_handle_t* handle, const char* bundle_id);
idb_error_t idb_companion_list_apps(idb_companion_handle_t* handle, 
                                    char*** bundle_ids, size_t* count);
void idb_companion_free_app_list(char** bundle_ids, size_t count);

// Async request handling (for operations that need streaming)
idb_error_t idb_companion_create_request(idb_companion_handle_t* handle,
                                         const char* method,
                                         idb_request_handle_t** request);
idb_error_t idb_companion_request_add_param(idb_request_handle_t* request,
                                             const char* key, const char* value);
idb_error_t idb_companion_request_add_data(idb_request_handle_t* request,
                                            const uint8_t* data, size_t size);
idb_error_t idb_companion_request_execute(idb_request_handle_t* request,
                                          idb_completion_callback callback,
                                          void* context);
idb_error_t idb_companion_request_execute_streaming(idb_request_handle_t* request,
                                                    idb_data_callback callback,
                                                    void* context);
void idb_companion_request_destroy(idb_request_handle_t* request);

// Logging
idb_error_t idb_companion_set_log_callback(idb_companion_handle_t* handle,
                                            idb_log_callback callback,
                                            void* context);
idb_error_t idb_companion_set_log_level(idb_companion_handle_t* handle, int level);

// Utility
const char* idb_companion_error_string(idb_error_t error);
const char* idb_companion_version(void);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_EMBEDDED_H