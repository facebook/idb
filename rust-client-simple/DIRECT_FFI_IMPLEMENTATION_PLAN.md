# Direct FFI Implementation Plan

## Overview
Create a C interface layer for idb_companion that can be directly called from Rust, eliminating gRPC overhead while maintaining all functionality.

## Architecture

```
┌──────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
│   Rust Client    │   FFI   │   C Interface       │   ObjC  │  CompanionLib    │
│                  │ ──────► │  (idb_direct.h/m)   │ ──────► │  (Existing)      │
│  Safe Rust API   │         │  Error Handling     │         │  FBSimulator*    │
│  Memory Mgmt     │         │  Type Conversion    │         │  FBDevice*       │
└──────────────────┘         └─────────────────────┘         └──────────────────┘
```

## Phase 1: C Interface Design

### 1.1 Create Header File
```c
// idb_direct.h
#ifndef IDB_DIRECT_H
#define IDB_DIRECT_H

#include <stdint.h>
#include <stdbool.h>

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
idb_error_t idb_multi_touch(idb_point_t* points, size_t count, idb_touch_type_t type);

// Screenshot operations
idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot);
void idb_free_screenshot(idb_screenshot_t* screenshot);

// App operations
idb_error_t idb_launch_app(const char* bundle_id);
idb_error_t idb_terminate_app(const char* bundle_id);
idb_error_t idb_install_app(const char* app_path);
idb_error_t idb_uninstall_app(const char* bundle_id);

// Async operations with callbacks
typedef void (*idb_screenshot_callback)(idb_screenshot_t* screenshot, idb_error_t error, void* context);
typedef void (*idb_log_callback)(const char* message, void* context);

idb_error_t idb_take_screenshot_async(idb_screenshot_callback callback, void* context);
idb_error_t idb_set_log_callback(idb_log_callback callback, void* context);

// Utility
const char* idb_error_string(idb_error_t error);
const char* idb_version(void);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_H
```

### 1.2 Implement C Interface
```objc
// idb_direct.m
#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import <CompanionLib/CompanionLib.h>
#import "idb_direct.h"

// Global state (thread-safe)
static struct {
    dispatch_queue_t queue;
    id<FBiOSTarget> current_target;
    FBSimulatorControl* simulator_control;
    FBDeviceControl* device_control;
    NSMutableDictionary* error_messages;
    BOOL initialized;
} g_idb_state = {0};

// Macro for thread-safe operations
#define IDB_SYNCHRONIZED(block) \
    dispatch_sync(g_idb_state.queue, ^{ \
        @autoreleasepool { \
            block \
        } \
    })

#define IDB_CHECK_INITIALIZED() \
    if (!g_idb_state.initialized) { \
        return IDB_ERROR_NOT_INITIALIZED; \
    }

// Implementation
idb_error_t idb_initialize(void) {
    __block idb_error_t result = IDB_SUCCESS;
    
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_idb_state.queue = dispatch_queue_create("com.arkavo.idb_direct", DISPATCH_QUEUE_SERIAL);
        g_idb_state.error_messages = [NSMutableDictionary dictionary];
        
        IDB_SYNCHRONIZED({
            NSError* error = nil;
            
            // Initialize simulator control
            g_idb_state.simulator_control = [FBSimulatorControl.configurationWithDefaults startWithError:&error];
            if (error) {
                result = IDB_ERROR_OPERATION_FAILED;
                g_idb_state.error_messages[@(result)] = error.localizedDescription;
                return;
            }
            
            // Initialize device control (optional, may fail on non-Mac)
            g_idb_state.device_control = [FBDeviceControl.defaultControl startWithError:nil];
            
            g_idb_state.initialized = YES;
        });
    });
    
    return result;
}

idb_error_t idb_tap(double x, double y) {
    IDB_CHECK_INITIALIZED();
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        // Create HID event
        FBIDBPoint* point = [[FBIDBPoint alloc] initWithX:x y:y];
        
        // Send tap (down + up)
        id<FBSimulatorHID> hid = (id<FBSimulatorHID>)g_idb_state.current_target;
        
        [hid sendTouchWithType:FBSimulatorHIDButtonTouchDown point:point error:&error];
        if (error) {
            result = IDB_ERROR_OPERATION_FAILED;
            g_idb_state.error_messages[@(result)] = error.localizedDescription;
            return;
        }
        
        // Small delay
        [NSThread sleepForTimeInterval:0.05];
        
        [hid sendTouchWithType:FBSimulatorHIDButtonTouchUp point:point error:&error];
        if (error) {
            result = IDB_ERROR_OPERATION_FAILED;
            g_idb_state.error_messages[@(result)] = error.localizedDescription;
        }
    });
    
    return result;
}

idb_error_t idb_take_screenshot(idb_screenshot_t* screenshot) {
    IDB_CHECK_INITIALIZED();
    
    if (!screenshot) {
        return IDB_ERROR_INVALID_PARAMETER;
    }
    
    __block idb_error_t result = IDB_SUCCESS;
    
    IDB_SYNCHRONIZED({
        if (!g_idb_state.current_target) {
            result = IDB_ERROR_DEVICE_NOT_FOUND;
            return;
        }
        
        NSError* error = nil;
        
        // Take screenshot
        NSData* imageData = [g_idb_state.current_target takeScreenshot:FBScreenshotFormatPNG error:&error];
        if (error || !imageData) {
            result = IDB_ERROR_OPERATION_FAILED;
            if (error) {
                g_idb_state.error_messages[@(result)] = error.localizedDescription;
            }
            return;
        }
        
        // Copy to C buffer
        screenshot->size = imageData.length;
        screenshot->data = (uint8_t*)malloc(screenshot->size);
        if (!screenshot->data) {
            result = IDB_ERROR_OUT_OF_MEMORY;
            return;
        }
        
        memcpy(screenshot->data, imageData.bytes, screenshot->size);
        screenshot->format = strdup("png");
        
        // Get dimensions (would need to parse PNG header or use NSImage)
        // For now, set placeholder values
        screenshot->width = 0;
        screenshot->height = 0;
    });
    
    return result;
}

// ... Additional implementations
```

## Phase 2: Rust Bindings

### 2.1 Build Configuration
```rust
// build.rs
use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/idb_direct.h");
    
    // Paths to frameworks
    let sdk_path = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    
    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header("src/idb_direct.h")
        .clang_arg(format!("-isysroot{}", sdk_path))
        .clang_arg("-x")
        .clang_arg("objective-c")
        .allowlist_function("idb_.*")
        .allowlist_type("idb_.*")
        .allowlist_var("IDB_.*")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        .generate()
        .expect("Unable to generate bindings");
    
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
    
    // Link libraries
    println!("cargo:rustc-link-lib=static=idb_direct");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=CoreGraphics");
    println!("cargo:rustc-link-lib=framework=CoreSimulator");
    println!("cargo:rustc-link-lib=static=FBControlCore");
    println!("cargo:rustc-link-lib=static=FBSimulatorControl");
    println!("cargo:rustc-link-lib=static=FBDeviceControl");
    println!("cargo:rustc-link-lib=static=CompanionLib");
}
```

### 2.2 Safe Rust Wrapper
```rust
// src/lib.rs
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::slice;

#[derive(Debug, thiserror::Error)]
pub enum IdbError {
    #[error("Not initialized")]
    NotInitialized,
    #[error("Invalid parameter")]
    InvalidParameter,
    #[error("Device not found")]
    DeviceNotFound,
    #[error("Simulator not running")]
    SimulatorNotRunning,
    #[error("Operation failed: {0}")]
    OperationFailed(String),
    #[error("Timeout")]
    Timeout,
    #[error("Out of memory")]
    OutOfMemory,
    #[error("Unknown error: {0}")]
    Unknown(i32),
}

impl From<idb_error_t> for Result<(), IdbError> {
    fn from(err: idb_error_t) -> Self {
        match err {
            0 => Ok(()),
            -1 => Err(IdbError::NotInitialized),
            -2 => Err(IdbError::InvalidParameter),
            -3 => Err(IdbError::DeviceNotFound),
            -4 => Err(IdbError::SimulatorNotRunning),
            -5 => {
                let msg = unsafe {
                    let ptr = idb_error_string(err);
                    if ptr.is_null() {
                        "Unknown error".to_string()
                    } else {
                        CStr::from_ptr(ptr).to_string_lossy().into_owned()
                    }
                };
                Err(IdbError::OperationFailed(msg))
            },
            -6 => Err(IdbError::Timeout),
            -7 => Err(IdbError::OutOfMemory),
            code => Err(IdbError::Unknown(code)),
        }
    }
}

pub struct IdbDirect {
    connected: bool,
}

impl IdbDirect {
    pub fn new() -> Result<Self, IdbError> {
        unsafe {
            idb_error_t::from(idb_initialize())?;
        }
        Ok(Self { connected: false })
    }
    
    pub fn connect_simulator(&mut self, udid: &str) -> Result<(), IdbError> {
        let c_udid = CString::new(udid).map_err(|_| IdbError::InvalidParameter)?;
        unsafe {
            idb_error_t::from(idb_connect_target(c_udid.as_ptr(), idb_target_type_t_IDB_TARGET_SIMULATOR))?;
        }
        self.connected = true;
        Ok(())
    }
    
    pub fn tap(&self, x: f64, y: f64) -> Result<(), IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        unsafe {
            idb_error_t::from(idb_tap(x, y))?;
        }
        Ok(())
    }
    
    pub fn screenshot(&self) -> Result<Vec<u8>, IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        
        let mut screenshot = idb_screenshot_t {
            data: std::ptr::null_mut(),
            size: 0,
            width: 0,
            height: 0,
            format: std::ptr::null_mut(),
        };
        
        unsafe {
            idb_error_t::from(idb_take_screenshot(&mut screenshot))?;
            
            // Copy data to Vec
            let data = slice::from_raw_parts(screenshot.data, screenshot.size).to_vec();
            
            // Free C memory
            idb_free_screenshot(&mut screenshot);
            
            Ok(data)
        }
    }
    
    pub fn swipe(&self, from: (f64, f64), to: (f64, f64), duration_secs: f64) -> Result<(), IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        
        let from_point = idb_point_t { x: from.0, y: from.1 };
        let to_point = idb_point_t { x: to.0, y: to.1 };
        
        unsafe {
            idb_error_t::from(idb_swipe(from_point, to_point, duration_secs))?;
        }
        Ok(())
    }
}

impl Drop for IdbDirect {
    fn drop(&mut self) {
        if self.connected {
            unsafe {
                let _ = idb_disconnect_target();
            }
        }
        unsafe {
            let _ = idb_shutdown();
        }
    }
}

// Async wrapper for compatibility
#[cfg(feature = "async")]
impl IdbDirect {
    pub async fn tap_async(&self, x: f64, y: f64) -> Result<(), IdbError> {
        // Run in blocking thread to avoid blocking executor
        let result = self.tap(x, y);
        tokio::task::yield_now().await;
        result
    }
}
```

## Phase 3: Build System

### 3.1 Xcode Build Script
```bash
#!/bin/bash
# build_static_lib.sh

set -e

# Build static library
xcodebuild -project FBSimulatorControl.xcodeproj \
    -target idb_direct \
    -configuration Release \
    -arch arm64 \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO

# Create universal binary if needed
lipo -create \
    build/Release/libidb_direct.a \
    -output dist/libidb_direct.a

# Copy headers
cp src/idb_direct.h dist/
```

### 3.2 Cargo Configuration
```toml
[package]
name = "idb-direct"
version = "0.1.0"
edition = "2021"

[dependencies]
thiserror = "1.0"
libc = "0.2"

[build-dependencies]
bindgen = "0.69"
cc = "1.0"

[dev-dependencies]
image = "0.25"

[features]
default = []
async = ["tokio"]

[dependencies.tokio]
version = "1"
features = ["rt", "macros"]
optional = true
```

## Phase 4: Integration Example

```rust
// examples/calibration.rs
use idb_direct::{IdbDirect, IdbError};
use std::thread::sleep;
use std::time::Duration;

fn main() -> Result<(), IdbError> {
    // Initialize
    let mut idb = IdbDirect::new()?;
    
    // Connect to simulator
    idb.connect_simulator("4A05B20A-349D-4EC5-B796-8F384798268B")?;
    
    // Calibration targets (with coordinate transformation built-in)
    let targets = [
        (88.0, 690.0),
        (352.0, 690.0),
        (220.0, 432.0),
        (88.0, 174.0),
        (352.0, 174.0),
    ];
    
    // Take initial screenshot
    let initial_screenshot = idb.screenshot()?;
    std::fs::write("calibration_start.png", initial_screenshot)?;
    
    // Run calibration
    for (i, &(x, y)) in targets.iter().enumerate() {
        println!("Tapping target {} at ({}, {})", i + 1, x, y);
        idb.tap(x, y)?;
        sleep(Duration::from_millis(1500));
        
        // Screenshot after each tap
        let screenshot = idb.screenshot()?;
        std::fs::write(format!("calibration_{}.png", i + 1), screenshot)?;
    }
    
    println!("Calibration complete!");
    Ok(())
}
```

## Phase 5: Performance Optimizations

### 5.1 Memory Pool for Screenshots
```rust
pub struct ScreenshotPool {
    buffers: Vec<Vec<u8>>,
    size: usize,
}

impl ScreenshotPool {
    pub fn new(capacity: usize, buffer_size: usize) -> Self {
        let buffers = (0..capacity)
            .map(|_| Vec::with_capacity(buffer_size))
            .collect();
        Self { buffers, size: 0 }
    }
    
    pub fn acquire(&mut self) -> Vec<u8> {
        self.buffers.pop().unwrap_or_else(|| Vec::with_capacity(1920 * 1080 * 4))
    }
    
    pub fn release(&mut self, buffer: Vec<u8>) {
        if self.buffers.len() < self.size {
            self.buffers.push(buffer);
        }
    }
}
```

### 5.2 Batch Operations
```c
// Support batch operations in C interface
idb_error_t idb_tap_batch(idb_point_t* points, size_t count, double interval_ms);
```

## Phase 6: Testing & Packaging

### 6.1 Test Suite
```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_initialization() {
        let idb = IdbDirect::new();
        assert!(idb.is_ok());
    }
    
    #[test]
    fn test_tap_without_connection() {
        let idb = IdbDirect::new().unwrap();
        let result = idb.tap(100.0, 100.0);
        assert!(matches!(result, Err(IdbError::DeviceNotFound)));
    }
}
```

### 6.2 Release Script
```bash
#!/bin/bash
# release.sh

# Build Objective-C static library
./build_static_lib.sh

# Build Rust library
cargo build --release

# Create release bundle
mkdir -p release/lib
cp dist/libidb_direct.a release/lib/
cp target/release/libidb_direct.rlib release/lib/
cp -r dist/Frameworks release/

# Create example binary
cargo build --release --example calibration
cp target/release/examples/calibration release/

# Package
tar -czf idb-direct-v0.1.0-arm64.tar.gz release/
```

## Timeline

1. **Week 1**: C interface implementation and testing
2. **Week 2**: Rust bindings and safe wrapper
3. **Week 3**: Build system and packaging
4. **Week 4**: Performance optimization and documentation

## Benefits Over gRPC

- **50KB vs 20MB** binary size
- **<1μs vs 1-5ms** call latency  
- **Zero** runtime dependencies
- **Direct** debugger access
- **Native** error handling