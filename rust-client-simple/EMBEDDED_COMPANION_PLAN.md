# Plan: Embedded idb_companion in Rust Client

## Overview
Run idb_companion as an embedded library within the Rust client process, maintaining gRPC communication but eliminating the need for a separate server process.

## Architecture

```
┌─────────────────────────────────────┐
│       Single Process                 │
│                                     │
│  ┌─────────────┐  ┌──────────────┐ │
│  │ Rust Client │  │ idb_companion│ │
│  │             │  │   (library)  │ │
│  │  gRPC       │  │              │ │
│  │  Client ────┼──┼─► gRPC       │ │
│  │             │  │   Server     │ │
│  └─────────────┘  └──────────────┘ │
│                                     │
│        In-Process Communication     │
└─────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Build idb_companion as a Static Library

1. **Create new build target**
   ```bash
   # Add to idb_companion.xcodeproj:
   # - New target: idb_companion_static (Static Library)
   # - Include all CompanionLib sources
   # - Link required frameworks statically
   ```

2. **Export C interface**
   ```objc
   // idb_companion_embedded.h
   #ifdef __cplusplus
   extern "C" {
   #endif
   
   typedef struct {
       const char* grpc_port;
       const char* device_set_path;
       bool is_simulator;
   } IDBCompanionConfig;
   
   // Initialize and start the companion server
   int idb_companion_start(IDBCompanionConfig* config);
   
   // Stop the companion server
   int idb_companion_stop(void);
   
   // Check if server is running
   bool idb_companion_is_running(void);
   
   #ifdef __cplusplus
   }
   #endif
   ```

3. **Modify CompanionLib to support embedding**
   ```objc
   // Add embedded mode support
   @interface FBIDBCompanionServer (Embedded)
   + (instancetype)embeddedServerWithConfiguration:(FBIDBConfiguration *)configuration;
   - (BOOL)startInProcess:(NSError **)error;
   @end
   ```

### Phase 2: Rust FFI Bindings

1. **Create build script**
   ```rust
   // build.rs
   fn main() {
       // Link to idb_companion static library
       println!("cargo:rustc-link-lib=static=idb_companion_static");
       println!("cargo:rustc-link-lib=framework=Foundation");
       println!("cargo:rustc-link-lib=framework=CoreSimulator");
       println!("cargo:rustc-link-lib=framework=FBControlCore");
       
       // Generate FFI bindings
       let bindings = bindgen::Builder::default()
           .header("../idb_companion_embedded.h")
           .parse_callbacks(Box::new(bindgen::CargoCallbacks))
           .generate()
           .expect("Unable to generate bindings");
           
       let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
       bindings
           .write_to_file(out_path.join("bindings.rs"))
           .expect("Couldn't write bindings!");
   }
   ```

2. **Rust wrapper module**
   ```rust
   // src/embedded_companion.rs
   use std::ffi::CString;
   use std::sync::{Arc, Mutex};
   use std::thread;
   
   include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
   
   pub struct EmbeddedCompanion {
       config: IDBCompanionConfig,
       running: Arc<Mutex<bool>>,
   }
   
   impl EmbeddedCompanion {
       pub fn new(port: u16) -> Self {
           let config = IDBCompanionConfig {
               grpc_port: CString::new(format!("{}", port)).unwrap().into_raw(),
               device_set_path: std::ptr::null(),
               is_simulator: true,
           };
           
           Self {
               config,
               running: Arc::new(Mutex::new(false)),
           }
       }
       
       pub fn start(&mut self) -> Result<(), String> {
           let result = unsafe { idb_companion_start(&mut self.config) };
           if result == 0 {
               *self.running.lock().unwrap() = true;
               Ok(())
           } else {
               Err(format!("Failed to start companion: {}", result))
           }
       }
       
       pub fn stop(&mut self) -> Result<(), String> {
           let result = unsafe { idb_companion_stop() };
           if result == 0 {
               *self.running.lock().unwrap() = false;
               Ok(())
           } else {
               Err(format!("Failed to stop companion: {}", result))
           }
       }
   }
   ```

### Phase 3: In-Process gRPC Communication

1. **Modified main.rs**
   ```rust
   mod embedded_companion;
   use embedded_companion::EmbeddedCompanion;
   
   #[tokio::main]
   async fn main() -> Result<(), Box<dyn std::error::Error>> {
       // Start embedded companion on a random port
       let port = 0; // Let OS assign port
       let mut companion = EmbeddedCompanion::new(port);
       companion.start()?;
       
       // Wait for server to be ready
       tokio::time::sleep(Duration::from_secs(1)).await;
       
       // Connect to in-process gRPC server
       let channel = Channel::from_static(&format!("http://127.0.0.1:{}", port))
           .connect()
           .await?;
           
       // Continue with normal client operations...
   }
   ```

2. **Alternative: Unix Domain Sockets**
   ```rust
   // For even better performance, use UDS instead of TCP
   let channel = Endpoint::from_static("http://[::1]:50051")
       .connect_with_connector(service_fn(|_: Uri| {
           UnixStream::connect("/tmp/idb_companion.sock")
       }))
       .await?;
   ```

### Phase 4: Build System Integration

1. **Cargo.toml additions**
   ```toml
   [build-dependencies]
   bindgen = "0.69"
   cc = "1.0"
   
   [dependencies]
   libc = "0.2"
   
   [features]
   embedded-companion = []
   ```

2. **Build script for XCFramework**
   ```bash
   #!/bin/bash
   # build_embedded_framework.sh
   
   xcodebuild -project idb_companion.xcodeproj \
       -scheme idb_companion_static \
       -configuration Release \
       -derivedDataPath build \
       BUILD_LIBRARY_FOR_DISTRIBUTION=YES
       
   # Create xcframework
   xcodebuild -create-xcframework \
       -library build/Build/Products/Release/libidb_companion_static.a \
       -headers CompanionLib/Headers \
       -output idb_companion_embedded.xcframework
   ```

### Phase 5: Memory Management & Safety

1. **Shared memory for screenshots**
   ```rust
   // Use shared memory for large data transfers
   use shared_memory::{Shmem, ShmemConf};
   
   pub struct SharedScreenshot {
       shmem: Shmem,
   }
   
   impl SharedScreenshot {
       pub fn capture(&mut self) -> Result<Vec<u8>, Error> {
           // Companion writes directly to shared memory
           // Avoiding serialization overhead
       }
   }
   ```

2. **Objective-C memory management**
   ```rust
   // Ensure proper ARC handling
   #[link(name = "objc")]
   extern "C" {
       fn objc_autoreleasePoolPush() -> *mut c_void;
       fn objc_autoreleasePoolPop(pool: *mut c_void);
   }
   
   struct AutoreleasePool(*mut c_void);
   
   impl AutoreleasePool {
       fn new() -> Self {
           unsafe { Self(objc_autoreleasePoolPush()) }
       }
   }
   
   impl Drop for AutoreleasePool {
       fn drop(&mut self) {
           unsafe { objc_autoreleasePoolPop(self.0) }
       }
   }
   ```

## Benefits

1. **Single binary distribution** - No need to manage separate processes
2. **Reduced latency** - In-process communication is faster
3. **Simplified deployment** - One executable to ship
4. **Better resource management** - Shared memory pool
5. **Easier debugging** - Single process to monitor

## Challenges & Solutions

1. **Objective-C Runtime in Rust**
   - Solution: Use `objc` crate for runtime management
   - Create autorelease pools for each operation

2. **Framework Dependencies**
   - Solution: Bundle frameworks with rpath modifications
   - Use static linking where possible

3. **Thread Safety**
   - Solution: Run companion on dedicated thread
   - Use message passing for cross-thread communication

4. **Signal Handling**
   - Solution: Unified signal handler for graceful shutdown
   - Ensure companion cleanup on exit

## Alternative Approach: Direct FFI (No gRPC)

For maximum performance, skip gRPC entirely:

```rust
// Direct Objective-C bridge
#[link(name = "CompanionLib")]
extern "C" {
    fn FBIDBCompanion_TapAtPoint(x: f64, y: f64) -> i32;
    fn FBIDBCompanion_TakeScreenshot(buffer: *mut u8, size: *mut usize) -> i32;
}

// Rust wrapper
pub fn tap(x: f64, y: f64) -> Result<(), Error> {
    let result = unsafe { FBIDBCompanion_TapAtPoint(x, y) };
    if result == 0 { Ok(()) } else { Err(Error::TapFailed) }
}
```

## Testing Strategy

1. **Unit tests** - Test FFI bindings in isolation
2. **Integration tests** - Full calibration sequence
3. **Performance benchmarks** - Compare with separate process
4. **Memory leak detection** - Valgrind/Instruments testing

## Next Steps

1. Prototype minimal embedded companion
2. Test in-process gRPC performance
3. Implement shared memory for screenshots
4. Bundle as single redistributable binary