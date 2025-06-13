#ifndef IDB_DIRECT_SHM_H
#define IDB_DIRECT_SHM_H

#include "idb_direct.h"
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shared memory handle
typedef struct idb_shm_handle* idb_shm_handle_t;

// Magic header for shared memory validation
#define IDB_SHM_MAGIC_HEADER 0x49444253484D0001ULL  // "IDBSHM" + version
#define IDB_SHM_MAX_SIZE (128 * 1024 * 1024)        // 128MB max
#define IDB_SHM_MIN_SIZE 1024                        // 1KB min

// Shared memory screenshot info with validation
typedef struct {
    uint64_t magic;           // Magic header for validation
    idb_shm_handle_t handle;
    void* base_address;
    size_t size;
    uint32_t width;
    uint32_t height;
    uint32_t bytes_per_row;
    char format[16];          // "BGRA", "RGB", etc.
    uint32_t checksum;        // Simple checksum for integrity
} idb_shm_screenshot_t;

// Shared memory operations
idb_error_t idb_shm_create(size_t size, idb_shm_handle_t* handle);
idb_error_t idb_shm_attach(idb_shm_handle_t handle, void** address);
idb_error_t idb_shm_detach(void* address);
idb_error_t idb_shm_destroy(idb_shm_handle_t handle);

// Screenshot operations with shared memory
idb_error_t idb_take_screenshot_shm(idb_shm_screenshot_t* screenshot);
void idb_free_screenshot_shm(idb_shm_screenshot_t* screenshot);

// Screenshot callback with zero-copy shared memory
typedef void (*idb_screenshot_shm_callback)(const idb_shm_screenshot_t* screenshot, void* context);
idb_error_t idb_screenshot_stream_shm(idb_screenshot_shm_callback callback, void* context, uint32_t fps);
idb_error_t idb_screenshot_stream_stop(void);

// Get shared memory key for cross-process access
const char* idb_shm_get_key(idb_shm_handle_t handle);

// Validation functions
idb_error_t idb_shm_validate_screenshot(const idb_shm_screenshot_t* screenshot);
uint32_t idb_shm_calculate_checksum(const idb_shm_screenshot_t* screenshot);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_SHM_H