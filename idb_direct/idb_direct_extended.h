#ifndef IDB_DIRECT_EXTENDED_H
#define IDB_DIRECT_EXTENDED_H

#include "idb_direct.h"

#ifdef __cplusplus
extern "C" {
#endif

// Extended error codes are now in idb_direct.h

// App launch options
typedef struct {
    const char** environment_variables;  // NULL-terminated array of "KEY=VALUE" strings
    const char** arguments;             // NULL-terminated array of arguments
    bool wait_for_debugger;
    bool kill_existing;
} idb_launch_options_t;

// Log streaming callback
typedef void (*idb_log_callback)(const char* line, void* context);

// File transfer progress callback
typedef void (*idb_progress_callback)(size_t bytes_transferred, size_t total_bytes, void* context);

// App Management
idb_error_t idb_install_app(const char* app_path, idb_progress_callback progress, void* context);
idb_error_t idb_uninstall_app(const char* bundle_id);
idb_error_t idb_launch_app(const char* bundle_id, const idb_launch_options_t* options);
idb_error_t idb_terminate_app(const char* bundle_id);
idb_error_t idb_list_apps(char*** bundle_ids, size_t* count);
void idb_free_app_list(char** bundle_ids, size_t count);

// Log Streaming
idb_error_t idb_start_log_stream(idb_log_callback callback, void* context);
idb_error_t idb_stop_log_stream(void);

// File Operations
idb_error_t idb_push_file(const char* local_path, const char* remote_path, idb_progress_callback progress, void* context);
idb_error_t idb_pull_file(const char* remote_path, const char* local_path, idb_progress_callback progress, void* context);
idb_error_t idb_mkdir(const char* remote_path);
idb_error_t idb_rm(const char* remote_path, bool recursive);
idb_error_t idb_ls(const char* remote_path, char*** entries, size_t* count);
void idb_free_ls_entries(char** entries, size_t count);

// Instruments/Tracing
idb_error_t idb_start_instruments_trace(const char* template_name, const char* output_path);
idb_error_t idb_stop_instruments_trace(void);

// Video Recording
idb_error_t idb_start_video_recording(const char* output_path);
idb_error_t idb_stop_video_recording(void);

// Simulator Control
idb_error_t idb_boot_simulator(const char* udid);
idb_error_t idb_shutdown_simulator(const char* udid);
idb_error_t idb_erase_simulator(const char* udid);
idb_error_t idb_clone_simulator(const char* source_udid, const char* new_name);

// Accessibility
idb_error_t idb_enable_accessibility(void);
idb_error_t idb_set_hardware_keyboard(bool enabled);
idb_error_t idb_set_locale(const char* locale_identifier);

// Advanced HID
idb_error_t idb_multi_touch(const idb_point_t* points, size_t point_count, idb_touch_type_t type);
idb_error_t idb_key_event(uint16_t keycode, bool down);
idb_error_t idb_text_input(const char* text);

// Memory Management Helpers
void idb_free_string(char* string);
void idb_free_string_array(char** strings, size_t count);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_EXTENDED_H