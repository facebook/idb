use std::ffi::CStr;
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::slice;
use std::time::{Duration, Instant};

// FFI bindings for shared memory API
#[repr(C)]
struct IdbShmHandle {
    _opaque: [u8; 0],
}

#[repr(C)]
struct IdbShmScreenshot {
    handle: *mut IdbShmHandle,
    base_address: *mut c_void,
    size: usize,
    width: u32,
    height: u32,
    bytes_per_row: u32,
    format: [c_char; 16],
}

extern "C" {
    fn idb_initialize() -> i32;
    fn idb_shutdown() -> i32;
    fn idb_connect_target(udid: *const c_char, target_type: i32) -> i32;
    fn idb_disconnect_target() -> i32;
    
    fn idb_take_screenshot_shm(screenshot: *mut IdbShmScreenshot) -> i32;
    fn idb_free_screenshot_shm(screenshot: *mut IdbShmScreenshot);
    fn idb_shm_get_key(handle: *mut IdbShmHandle) -> *const c_char;
    
    fn idb_screenshot_stream_shm(
        callback: extern "C" fn(*const IdbShmScreenshot, *mut c_void),
        context: *mut c_void,
        fps: u32,
    ) -> i32;
    fn idb_screenshot_stream_stop() -> i32;
}

// Callback for screenshot streaming
extern "C" fn screenshot_callback(screenshot: *const IdbShmScreenshot, _context: *mut c_void) {
    unsafe {
        let shot = &*screenshot;
        println!(
            "Frame: {}x{}, {} bytes, format: {}",
            shot.width,
            shot.height,
            shot.size,
            CStr::from_ptr(shot.format.as_ptr()).to_string_lossy()
        );
        
        if !shot.base_address.is_null() {
            // Access pixel data directly from shared memory
            let pixels = slice::from_raw_parts(shot.base_address as *const u8, shot.size);
            
            // Calculate simple checksum
            let checksum: u32 = pixels.iter()
                .step_by(1024)
                .fold(0u32, |acc, &byte| acc.wrapping_add(byte as u32));
            
            println!("  Data checksum: 0x{:08X}", checksum);
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("=== Rust Shared Memory Screenshot Example ===\n");
    
    unsafe {
        // Initialize IDB
        let err = idb_initialize();
        if err != 0 {
            panic!("Failed to initialize IDB: {}", err);
        }
        
        // For this example, we'll use a hardcoded UDID
        // In real usage, you'd call idb_list_targets first
        let udid = std::ffi::CString::new("booted")?;
        let err = idb_connect_target(udid.as_ptr(), 0); // 0 = simulator
        if err != 0 {
            panic!("Failed to connect to simulator: {}", err);
        }
        
        // Test 1: Single screenshot with shared memory
        println!("Test 1: Single Screenshot");
        let mut screenshot: IdbShmScreenshot = std::mem::zeroed();
        let err = idb_take_screenshot_shm(&mut screenshot);
        
        if err == 0 {
            println!(
                "Screenshot: {}x{}, {} bytes",
                screenshot.width, screenshot.height, screenshot.size
            );
            
            // Get shared memory key
            let key_ptr = idb_shm_get_key(screenshot.handle);
            if !key_ptr.is_null() {
                let key = CStr::from_ptr(key_ptr).to_string_lossy();
                println!("Shared memory key: {}", key);
            }
            
            // Access pixel data
            if !screenshot.base_address.is_null() {
                let pixels = slice::from_raw_parts(
                    screenshot.base_address as *const u8,
                    screenshot.size,
                );
                
                // Example: Extract center pixel (assuming BGRA format)
                let center_offset = (screenshot.height / 2) as usize * screenshot.bytes_per_row as usize
                    + (screenshot.width / 2) as usize * 4;
                
                if center_offset + 4 <= pixels.len() {
                    let b = pixels[center_offset];
                    let g = pixels[center_offset + 1];
                    let r = pixels[center_offset + 2];
                    let a = pixels[center_offset + 3];
                    println!("Center pixel: R={}, G={}, B={}, A={}", r, g, b, a);
                }
            }
            
            // Free the screenshot
            idb_free_screenshot_shm(&mut screenshot);
        } else {
            println!("Screenshot failed: {}", err);
        }
        
        // Test 2: Screenshot streaming
        println!("\nTest 2: Screenshot Stream (3 seconds at 5 FPS)");
        let err = idb_screenshot_stream_shm(screenshot_callback, ptr::null_mut(), 5);
        if err == 0 {
            println!("Streaming started...");
            std::thread::sleep(Duration::from_secs(3));
            
            let err = idb_screenshot_stream_stop();
            println!("Streaming stopped: {}", err);
        }
        
        // Test 3: Performance benchmark
        println!("\nTest 3: Performance Benchmark");
        let start = Instant::now();
        let mut success_count = 0;
        
        for _ in 0..50 {
            let mut shot: IdbShmScreenshot = std::mem::zeroed();
            if idb_take_screenshot_shm(&mut shot) == 0 {
                success_count += 1;
                idb_free_screenshot_shm(&mut shot);
            }
        }
        
        let elapsed = start.elapsed();
        let fps = success_count as f64 / elapsed.as_secs_f64();
        println!(
            "Captured {} screenshots in {:.2}s ({:.1} FPS)",
            success_count,
            elapsed.as_secs_f64(),
            fps
        );
        
        // Cleanup
        idb_disconnect_target();
        idb_shutdown();
    }
    
    println!("\nExample completed successfully!");
    Ok(())
}