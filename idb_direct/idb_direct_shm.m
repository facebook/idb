/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <sys/mman.h>
#import <unistd.h>
#import "idb_direct_shm.h"

// Internal structure for shared memory handle
struct idb_shm_handle {
    mach_port_t memory_object;
    mach_vm_size_t size;
    char key[64];
};

// Static variables for screenshot streaming
static dispatch_source_t g_screenshot_timer = nil;
static idb_screenshot_shm_callback g_screenshot_callback = NULL;
static void* g_screenshot_context = NULL;
static idb_shm_screenshot_t* g_current_screenshot = NULL;

#pragma mark - Shared Memory Management

idb_error_t idb_shm_create(size_t size, idb_shm_handle_t* handle) {
    if (!handle || size == 0) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Bounds checking for shared memory size
    if (size < IDB_SHM_MIN_SIZE || size > IDB_SHM_MAX_SIZE) {
        NSLog(@"idb_shm: Invalid size %zu (min: %d, max: %d)", size, IDB_SHM_MIN_SIZE, IDB_SHM_MAX_SIZE);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Allocate handle
    struct idb_shm_handle* h = calloc(1, sizeof(struct idb_shm_handle));
    if (!h) {
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    
    // Create anonymous shared memory using mach_vm
    mach_port_t memory_object = MACH_PORT_NULL;
    h->size = size;
    
    // Allocate memory first
    mach_vm_address_t addr = 0;
    kern_return_t kr = mach_vm_allocate(mach_task_self(), &addr, size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        free(h);
        NSLog(@"idb_shm: Failed to allocate memory: %s", mach_error_string(kr));
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Create memory entry from the allocated region
    memory_object_size_t entry_size = size;
    kr = mach_make_memory_entry_64(
        mach_task_self(),
        &entry_size,
        addr,
        VM_PROT_READ | VM_PROT_WRITE,
        &memory_object,
        MACH_PORT_NULL
    );
    
    // Deallocate the original allocation
    mach_vm_deallocate(mach_task_self(), addr, size);
    
    if (kr != KERN_SUCCESS) {
        free(h);
        NSLog(@"idb_shm: Failed to create memory entry: %s", mach_error_string(kr));
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    h->memory_object = memory_object;
    
    // Generate unique key
    snprintf(h->key, sizeof(h->key), "idb_shm_%d_%llu", getpid(), mach_absolute_time());
    
    *handle = h;
    return IDB_SUCCESS;
}

idb_error_t idb_shm_attach(idb_shm_handle_t handle, void** address) {
    if (!handle || !address) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Bounds check the handle size
    if (handle->size < IDB_SHM_MIN_SIZE || handle->size > IDB_SHM_MAX_SIZE) {
        NSLog(@"idb_shm: Invalid handle size %llu (min: %d, max: %d)", 
              (unsigned long long)handle->size, IDB_SHM_MIN_SIZE, IDB_SHM_MAX_SIZE);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    mach_vm_address_t addr = 0;
    kern_return_t kr = mach_vm_map(
        mach_task_self(),
        &addr,
        handle->size,
        0,
        VM_FLAGS_ANYWHERE,
        handle->memory_object,
        0,
        FALSE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_INHERIT_SHARE
    );
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"idb_shm: Failed to map memory: %s", mach_error_string(kr));
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    *address = (void*)addr;
    return IDB_SUCCESS;
}

idb_error_t idb_shm_detach(void* address) {
    if (!address) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Get the memory region size
    mach_vm_address_t addr = (mach_vm_address_t)address;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    kern_return_t kr = mach_vm_region(
        mach_task_self(),
        &addr,
        &size,
        VM_REGION_BASIC_INFO_64,
        (vm_region_info_t)&info,
        &count,
        &object_name
    );
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"idb_shm: Failed to get memory region info: %s", mach_error_string(kr));
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Bounds check the region size
    if (size < IDB_SHM_MIN_SIZE || size > IDB_SHM_MAX_SIZE) {
        NSLog(@"idb_shm: Invalid region size %llu during detach (min: %d, max: %d)", 
              (unsigned long long)size, IDB_SHM_MIN_SIZE, IDB_SHM_MAX_SIZE);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Unmap the memory
    kr = mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)address, size);
    if (kr != KERN_SUCCESS) {
        NSLog(@"idb_shm: Failed to deallocate memory: %s", mach_error_string(kr));
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    return IDB_SUCCESS;
}

idb_error_t idb_shm_destroy(idb_shm_handle_t handle) {
    if (!handle) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Release the memory object port
    if (handle->memory_object != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), handle->memory_object);
    }
    
    free(handle);
    return IDB_SUCCESS;
}

const char* idb_shm_get_key(idb_shm_handle_t handle) {
    return handle ? handle->key : NULL;
}

#pragma mark - Validation Functions

uint32_t idb_shm_calculate_checksum(const idb_shm_screenshot_t* screenshot) {
    if (!screenshot) {
        return 0;
    }
    
    // Simple checksum of critical fields (excluding checksum field itself)
    uint32_t checksum = 0;
    checksum ^= (uint32_t)(screenshot->magic >> 32);
    checksum ^= (uint32_t)(screenshot->magic & 0xFFFFFFFF);
    checksum ^= (uint32_t)(screenshot->size >> 32);
    checksum ^= (uint32_t)(screenshot->size & 0xFFFFFFFF);
    checksum ^= screenshot->width;
    checksum ^= screenshot->height;
    checksum ^= screenshot->bytes_per_row;
    
    // Include format string in checksum
    for (int i = 0; i < 16 && screenshot->format[i]; i++) {
        checksum ^= (uint32_t)screenshot->format[i] << (8 * (i % 4));
    }
    
    return checksum;
}

idb_error_t idb_shm_validate_screenshot(const idb_shm_screenshot_t* screenshot) {
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check magic header
    if (screenshot->magic != IDB_SHM_MAGIC_HEADER) {
        NSLog(@"idb_shm: Invalid magic header 0x%llx (expected 0x%llx)", 
              screenshot->magic, IDB_SHM_MAGIC_HEADER);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check size bounds
    if (screenshot->size < IDB_SHM_MIN_SIZE || screenshot->size > IDB_SHM_MAX_SIZE) {
        NSLog(@"idb_shm: Invalid size %zu (min: %d, max: %d)", 
              screenshot->size, IDB_SHM_MIN_SIZE, IDB_SHM_MAX_SIZE);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check dimensions are reasonable
    if (screenshot->width == 0 || screenshot->height == 0 || 
        screenshot->width > 8192 || screenshot->height > 8192) {
        NSLog(@"idb_shm: Invalid dimensions %ux%u", screenshot->width, screenshot->height);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check bytes per row makes sense
    uint32_t min_bytes_per_row = screenshot->width * 3; // RGB minimum
    uint32_t max_bytes_per_row = screenshot->width * 4; // RGBA maximum
    if (screenshot->bytes_per_row < min_bytes_per_row || screenshot->bytes_per_row > max_bytes_per_row) {
        NSLog(@"idb_shm: Invalid bytes_per_row %u (expected %u-%u for width %u)", 
              screenshot->bytes_per_row, min_bytes_per_row, max_bytes_per_row, screenshot->width);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check total size matches dimensions
    size_t expected_size = screenshot->bytes_per_row * screenshot->height;
    if (screenshot->size < expected_size) {
        NSLog(@"idb_shm: Size %zu too small for dimensions (expected at least %zu)", 
              screenshot->size, expected_size);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Verify checksum
    uint32_t calculated_checksum = idb_shm_calculate_checksum(screenshot);
    if (screenshot->checksum != calculated_checksum) {
        NSLog(@"idb_shm: Checksum mismatch 0x%x (expected 0x%x)", 
              screenshot->checksum, calculated_checksum);
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check base address is valid
    if (!screenshot->base_address) {
        NSLog(@"idb_shm: Invalid base address");
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Check format string is null-terminated
    bool format_terminated = false;
    for (int i = 0; i < 16; i++) {
        if (screenshot->format[i] == '\0') {
            format_terminated = true;
            break;
        }
    }
    if (!format_terminated) {
        NSLog(@"idb_shm: Format string not null-terminated");
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    return IDB_SUCCESS;
}

#pragma mark - Screenshot Operations

// Import necessary functions from the main implementation
extern idb_error_t idb_initialize(void);
extern id g_idb_state_current_device(void);
extern const char* idb_error_string(idb_error_t error);

idb_error_t idb_take_screenshot_shm(idb_shm_screenshot_t* screenshot) {
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    @autoreleasepool {
        // Ensure initialized
        idb_error_t err = idb_initialize();
        if (err != IDB_SUCCESS) {
            return err;
        }
        
        // Get current device from real implementation
        id device = g_idb_state_current_device();
        if (!device) {
            return IDB_ERROR_DEVICE_NOT_FOUND;
        }
        
        // Take screenshot using private API
        SEL screenshotSelector = NSSelectorFromString(@"screenshot");
        if (![device respondsToSelector:screenshotSelector]) {
            return IDB_ERROR_UNSUPPORTED;
        }
        
        // Get screenshot data
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSData* imageData = [device performSelector:screenshotSelector];
#pragma clang diagnostic pop
        if (!imageData) {
            return IDB_ERROR_OPERATION_FAILED;
        }
        
        // Create CGImage from data
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
        if (!source) {
            return IDB_ERROR_OPERATION_FAILED;
        }
        
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        
        if (!image) {
            return IDB_ERROR_OPERATION_FAILED;
        }
        
        // Get image properties
        size_t width = CGImageGetWidth(image);
        size_t height = CGImageGetHeight(image);
        size_t bytesPerRow = CGImageGetBytesPerRow(image);
        size_t bitsPerPixel = CGImageGetBitsPerPixel(image);
        size_t size = bytesPerRow * height;
        
        // Create shared memory for the image
        idb_shm_handle_t handle;
        err = idb_shm_create(size, &handle);
        if (err != IDB_SUCCESS) {
            CGImageRelease(image);
            return err;
        }
        
        // Map the shared memory
        void* base_address;
        err = idb_shm_attach(handle, &base_address);
        if (err != IDB_SUCCESS) {
            idb_shm_destroy(handle);
            CGImageRelease(image);
            return err;
        }
        
        // Get raw pixel data
        CGDataProviderRef provider = CGImageGetDataProvider(image);
        CFDataRef data = CGDataProviderCopyData(provider);
        
        if (data) {
            // Copy image data to shared memory
            memcpy(base_address, CFDataGetBytePtr(data), size);
            CFRelease(data);
        } else {
            // Fallback: render to bitmap context
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(
                base_address,
                width,
                height,
                8,
                bytesPerRow,
                colorSpace,
                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
            );
            
            if (context) {
                CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
                CGContextRelease(context);
            }
            
            CGColorSpaceRelease(colorSpace);
        }
        
        CGImageRelease(image);
        
        // Fill in screenshot info with validation
        screenshot->magic = IDB_SHM_MAGIC_HEADER;
        screenshot->handle = handle;
        screenshot->base_address = base_address;
        screenshot->size = size;
        screenshot->width = (uint32_t)width;
        screenshot->height = (uint32_t)height;
        screenshot->bytes_per_row = (uint32_t)bytesPerRow;
        
        // Determine format
        if (bitsPerPixel == 32) {
            strlcpy(screenshot->format, "BGRA", sizeof(screenshot->format));
        } else if (bitsPerPixel == 24) {
            strlcpy(screenshot->format, "RGB", sizeof(screenshot->format));
        } else {
            strlcpy(screenshot->format, "UNKNOWN", sizeof(screenshot->format));
        }
        
        // Calculate and set checksum
        screenshot->checksum = idb_shm_calculate_checksum(screenshot);
        
        // Validate the complete structure
        err = idb_shm_validate_screenshot(screenshot);
        if (err != IDB_SUCCESS) {
            NSLog(@"idb_shm: Screenshot validation failed");
            idb_shm_detach(base_address);
            idb_shm_destroy(handle);
            return err;
        }
        
        return IDB_SUCCESS;
    }
}

void idb_free_screenshot_shm(idb_shm_screenshot_t* screenshot) {
    if (!screenshot) {
        return;
    }
    
    // Validate before freeing (log warning if invalid)
    if (idb_shm_validate_screenshot(screenshot) != IDB_SUCCESS) {
        NSLog(@"idb_shm: Warning - freeing invalid screenshot structure");
    }
    
    if (screenshot->base_address) {
        idb_shm_detach(screenshot->base_address);
        screenshot->base_address = NULL;
    }
    
    if (screenshot->handle) {
        idb_shm_destroy(screenshot->handle);
        screenshot->handle = NULL;
    }
    
    // Clear magic header to prevent reuse
    screenshot->magic = 0;
    screenshot->checksum = 0;
}

#pragma mark - Screenshot Streaming

idb_error_t idb_screenshot_stream_shm(idb_screenshot_shm_callback callback, void* context, uint32_t fps) {
    if (!callback || fps == 0 || fps > 60) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    // Stop any existing stream
    idb_screenshot_stream_stop();
    
    g_screenshot_callback = callback;
    g_screenshot_context = context;
    
    // Allocate screenshot buffer
    g_current_screenshot = calloc(1, sizeof(idb_shm_screenshot_t));
    if (!g_current_screenshot) {
        return IDB_ERROR_OUT_OF_MEMORY;
    }
    
    // Create timer for periodic screenshots
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    g_screenshot_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    if (!g_screenshot_timer) {
        free(g_current_screenshot);
        g_current_screenshot = NULL;
        return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Set timer interval based on FPS
    uint64_t interval = NSEC_PER_SEC / fps;
    dispatch_source_set_timer(g_screenshot_timer, 
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              interval,
                              interval / 10); // 10% leeway
    
    dispatch_source_set_event_handler(g_screenshot_timer, ^{
        // Free previous screenshot
        if (g_current_screenshot->handle) {
            idb_free_screenshot_shm(g_current_screenshot);
        }
        
        // Take new screenshot
        idb_error_t err = idb_take_screenshot_shm(g_current_screenshot);
        if (err == IDB_SUCCESS) {
            // Validate screenshot before callback
            err = idb_shm_validate_screenshot(g_current_screenshot);
            if (err == IDB_SUCCESS) {
                // Call callback with validated screenshot
                g_screenshot_callback(g_current_screenshot, g_screenshot_context);
            } else {
                NSLog(@"idb_shm: Screenshot validation failed: %s", idb_error_string(err));
            }
        } else {
            NSLog(@"idb_shm: Screenshot failed: %s", idb_error_string(err));
        }
    });
    
    dispatch_resume(g_screenshot_timer);
    
    NSLog(@"idb_shm: Started screenshot stream at %u FPS", fps);
    return IDB_SUCCESS;
}

idb_error_t idb_screenshot_stream_stop(void) {
    if (g_screenshot_timer) {
        dispatch_source_cancel(g_screenshot_timer);
        g_screenshot_timer = nil;
    }
    
    if (g_current_screenshot) {
        idb_free_screenshot_shm(g_current_screenshot);
        free(g_current_screenshot);
        g_current_screenshot = NULL;
    }
    
    g_screenshot_callback = NULL;
    g_screenshot_context = NULL;
    
    NSLog(@"idb_shm: Stopped screenshot stream");
    return IDB_SUCCESS;
}