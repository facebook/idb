/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "idb_direct_extended.h"

#pragma mark - App Management

idb_error_t idb_install_app(const char* app_path, idb_progress_callback progress, void* context) {
    NSLog(@"idb_direct: install_app not implemented yet - path: %s", app_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_uninstall_app(const char* bundle_id) {
    NSLog(@"idb_direct: uninstall_app not implemented yet - bundle: %s", bundle_id);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_launch_app(const char* bundle_id, const idb_launch_options_t* options) {
    NSLog(@"idb_direct: launch_app not implemented yet - bundle: %s", bundle_id);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_terminate_app(const char* bundle_id) {
    NSLog(@"idb_direct: terminate_app not implemented yet - bundle: %s", bundle_id);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_list_apps(char*** bundle_ids, size_t* count) {
    NSLog(@"idb_direct: list_apps not implemented yet");
    return IDB_ERROR_NOT_IMPLEMENTED;
}

void idb_free_app_list(char** bundle_ids, size_t count) {
    if (!bundle_ids) return;
    
    for (size_t i = 0; i < count; i++) {
        free(bundle_ids[i]);
    }
    free(bundle_ids);
}

#pragma mark - Log Streaming

static idb_log_callback g_log_callback = NULL;
static void* g_log_context = NULL;

idb_error_t idb_start_log_stream(idb_log_callback callback, void* context) {
    NSLog(@"idb_direct: start_log_stream not implemented yet");
    g_log_callback = callback;
    g_log_context = context;
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_stop_log_stream(void) {
    NSLog(@"idb_direct: stop_log_stream not implemented yet");
    g_log_callback = NULL;
    g_log_context = NULL;
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - File Operations

idb_error_t idb_push_file(const char* local_path, const char* remote_path, idb_progress_callback progress, void* context) {
    NSLog(@"idb_direct: push_file not implemented yet - %s -> %s", local_path, remote_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_pull_file(const char* remote_path, const char* local_path, idb_progress_callback progress, void* context) {
    NSLog(@"idb_direct: pull_file not implemented yet - %s -> %s", remote_path, local_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_mkdir(const char* remote_path) {
    NSLog(@"idb_direct: mkdir not implemented yet - %s", remote_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_rm(const char* remote_path, bool recursive) {
    NSLog(@"idb_direct: rm not implemented yet - %s (recursive: %d)", remote_path, recursive);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_ls(const char* remote_path, char*** entries, size_t* count) {
    NSLog(@"idb_direct: ls not implemented yet - %s", remote_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

void idb_free_ls_entries(char** entries, size_t count) {
    idb_free_string_array(entries, count);
}

#pragma mark - Instruments/Tracing

idb_error_t idb_start_instruments_trace(const char* template_name, const char* output_path) {
    NSLog(@"idb_direct: start_instruments_trace not implemented yet - template: %s, output: %s", 
          template_name, output_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_stop_instruments_trace(void) {
    NSLog(@"idb_direct: stop_instruments_trace not implemented yet");
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - Video Recording

idb_error_t idb_start_video_recording(const char* output_path) {
    NSLog(@"idb_direct: start_video_recording not implemented yet - %s", output_path);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_stop_video_recording(void) {
    NSLog(@"idb_direct: stop_video_recording not implemented yet");
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - Simulator Control

idb_error_t idb_boot_simulator(const char* udid) {
    NSLog(@"idb_direct: boot_simulator not implemented yet - %s", udid);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_shutdown_simulator(const char* udid) {
    NSLog(@"idb_direct: shutdown_simulator not implemented yet - %s", udid);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_erase_simulator(const char* udid) {
    NSLog(@"idb_direct: erase_simulator not implemented yet - %s", udid);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_clone_simulator(const char* source_udid, const char* new_name) {
    NSLog(@"idb_direct: clone_simulator not implemented yet - %s -> %s", source_udid, new_name);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - Accessibility

idb_error_t idb_enable_accessibility(void) {
    NSLog(@"idb_direct: enable_accessibility not implemented yet");
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_set_hardware_keyboard(bool enabled) {
    NSLog(@"idb_direct: set_hardware_keyboard not implemented yet - %d", enabled);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_set_locale(const char* locale_identifier) {
    NSLog(@"idb_direct: set_locale not implemented yet - %s", locale_identifier);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - Advanced HID

idb_error_t idb_multi_touch(const idb_point_t* points, size_t point_count, idb_touch_type_t type) {
    NSLog(@"idb_direct: multi_touch not implemented yet - %zu points", point_count);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_key_event(uint16_t keycode, bool down) {
    NSLog(@"idb_direct: key_event not implemented yet - keycode: %d, down: %d", keycode, down);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

idb_error_t idb_text_input(const char* text) {
    NSLog(@"idb_direct: text_input not implemented yet - %s", text);
    return IDB_ERROR_NOT_IMPLEMENTED;
}

#pragma mark - Memory Management

void idb_free_string(char* string) {
    free(string);
}

void idb_free_string_array(char** strings, size_t count) {
    if (!strings) return;
    
    for (size_t i = 0; i < count; i++) {
        free(strings[i]);
    }
    free(strings);
}