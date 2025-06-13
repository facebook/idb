// embedded.rs - Rust bindings for embedded idb_companion

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::slice;

// FFI bindings
#[repr(C)]
pub struct IdbCompanionHandle {
    _private: [u8; 0],
}

#[repr(C)]
pub struct IdbRequestHandle {
    _private: [u8; 0],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdbError {
    Success = 0,
    NotInitialized = -1,
    InvalidParameter = -2,
    DeviceNotFound = -3,
    SimulatorNotRunning = -4,
    OperationFailed = -5,
    Timeout = -6,
    OutOfMemory = -7,
    NotSupported = -8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdbTargetType {
    Simulator = 0,
    Device = 1,
}

// Callback types
pub type CompletionCallback = extern "C" fn(error: IdbError, result: *const c_void, context: *mut c_void);
pub type DataCallback = extern "C" fn(data: *const u8, size: usize, context: *mut c_void);
pub type LogCallback = extern "C" fn(message: *const c_char, level: i32, context: *mut c_void);

#[link(name = "idb_direct", kind = "static")]
extern "C" {
    // Companion lifecycle
    fn idb_companion_create(handle: *mut *mut IdbCompanionHandle) -> IdbError;
    fn idb_companion_destroy(handle: *mut IdbCompanionHandle) -> IdbError;
    
    // Target connection
    fn idb_companion_connect(
        handle: *mut IdbCompanionHandle,
        udid: *const c_char,
        target_type: IdbTargetType,
    ) -> IdbError;
    fn idb_companion_disconnect(handle: *mut IdbCompanionHandle) -> IdbError;
    
    // HID operations
    fn idb_companion_tap(handle: *mut IdbCompanionHandle, x: f64, y: f64) -> IdbError;
    fn idb_companion_swipe(
        handle: *mut IdbCompanionHandle,
        from_x: f64,
        from_y: f64,
        to_x: f64,
        to_y: f64,
        duration_seconds: f64,
    ) -> IdbError;
    
    // Screenshot
    fn idb_companion_screenshot(
        handle: *mut IdbCompanionHandle,
        data: *mut *mut u8,
        size: *mut usize,
        width: *mut u32,
        height: *mut u32,
    ) -> IdbError;
    fn idb_companion_free_screenshot(data: *mut u8);
    
    // App operations
    fn idb_companion_launch_app(
        handle: *mut IdbCompanionHandle,
        bundle_id: *const c_char,
    ) -> IdbError;
    fn idb_companion_terminate_app(
        handle: *mut IdbCompanionHandle,
        bundle_id: *const c_char,
    ) -> IdbError;
    fn idb_companion_list_apps(
        handle: *mut IdbCompanionHandle,
        bundle_ids: *mut *mut *mut c_char,
        count: *mut usize,
    ) -> IdbError;
    fn idb_companion_free_app_list(bundle_ids: *mut *mut c_char, count: usize);
    
    // Logging
    fn idb_companion_set_log_callback(
        handle: *mut IdbCompanionHandle,
        callback: Option<LogCallback>,
        context: *mut c_void,
    ) -> IdbError;
    
    // Utility
    fn idb_companion_error_string(error: IdbError) -> *const c_char;
    fn idb_companion_version() -> *const c_char;
}

// Safe Rust wrapper
pub struct EmbeddedCompanion {
    handle: *mut IdbCompanionHandle,
}

impl EmbeddedCompanion {
    pub fn new() -> Result<Self, IdbError> {
        let mut handle: *mut IdbCompanionHandle = ptr::null_mut();
        let result = unsafe { idb_companion_create(&mut handle) };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(EmbeddedCompanion { handle })
    }
    
    pub fn connect_simulator(&mut self, udid: &str) -> Result<(), IdbError> {
        let c_udid = CString::new(udid).map_err(|_| IdbError::InvalidParameter)?;
        let result = unsafe {
            idb_companion_connect(self.handle, c_udid.as_ptr(), IdbTargetType::Simulator)
        };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn tap(&self, x: f64, y: f64) -> Result<(), IdbError> {
        let result = unsafe { idb_companion_tap(self.handle, x, y) };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn swipe(&self, from: (f64, f64), to: (f64, f64), duration_secs: f64) -> Result<(), IdbError> {
        let result = unsafe {
            idb_companion_swipe(
                self.handle,
                from.0,
                from.1,
                to.0,
                to.1,
                duration_secs,
            )
        };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn screenshot(&self) -> Result<Vec<u8>, IdbError> {
        let mut data: *mut u8 = ptr::null_mut();
        let mut size: usize = 0;
        let mut width: u32 = 0;
        let mut height: u32 = 0;
        
        let result = unsafe {
            idb_companion_screenshot(
                self.handle,
                &mut data,
                &mut size,
                &mut width,
                &mut height,
            )
        };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        // Copy data to Vec
        let screenshot_data = unsafe { slice::from_raw_parts(data, size).to_vec() };
        
        // Free C memory
        unsafe { idb_companion_free_screenshot(data) };
        
        Ok(screenshot_data)
    }
    
    pub fn launch_app(&self, bundle_id: &str) -> Result<(), IdbError> {
        let c_bundle_id = CString::new(bundle_id).map_err(|_| IdbError::InvalidParameter)?;
        let result = unsafe { idb_companion_launch_app(self.handle, c_bundle_id.as_ptr()) };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn terminate_app(&self, bundle_id: &str) -> Result<(), IdbError> {
        let c_bundle_id = CString::new(bundle_id).map_err(|_| IdbError::InvalidParameter)?;
        let result = unsafe { idb_companion_terminate_app(self.handle, c_bundle_id.as_ptr()) };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn list_apps(&self) -> Result<Vec<String>, IdbError> {
        let mut bundle_ids: *mut *mut c_char = ptr::null_mut();
        let mut count: usize = 0;
        
        let result = unsafe {
            idb_companion_list_apps(self.handle, &mut bundle_ids, &mut count)
        };
        
        if result != IdbError::Success {
            return Err(result);
        }
        
        // Convert C strings to Rust strings
        let mut apps = Vec::with_capacity(count);
        for i in 0..count {
            unsafe {
                let bundle_id = CStr::from_ptr(*bundle_ids.add(i))
                    .to_string_lossy()
                    .into_owned();
                apps.push(bundle_id);
            }
        }
        
        // Free C memory
        unsafe { idb_companion_free_app_list(bundle_ids, count) };
        
        Ok(apps)
    }
    
    pub fn set_log_callback<F>(&self, callback: F) -> Result<(), IdbError>
    where
        F: Fn(&str, i32) + 'static,
    {
        // Store callback in a Box to ensure it lives long enough
        let callback_box = Box::new(callback);
        let callback_ptr = Box::into_raw(callback_box);
        
        extern "C" fn log_trampoline(message: *const c_char, level: i32, context: *mut c_void) {
            unsafe {
                let callback = &*(context as *const Box<dyn Fn(&str, i32)>);
                if let Ok(msg) = CStr::from_ptr(message).to_str() {
                    callback(msg, level);
                }
            }
        }
        
        let result = unsafe {
            idb_companion_set_log_callback(
                self.handle,
                Some(log_trampoline),
                callback_ptr as *mut c_void,
            )
        };
        
        if result != IdbError::Success {
            // Clean up callback if setting failed
            unsafe { Box::from_raw(callback_ptr) };
            return Err(result);
        }
        
        Ok(())
    }
    
    pub fn version() -> String {
        unsafe {
            CStr::from_ptr(idb_companion_version())
                .to_string_lossy()
                .into_owned()
        }
    }
    
    pub fn error_string(error: IdbError) -> String {
        unsafe {
            CStr::from_ptr(idb_companion_error_string(error))
                .to_string_lossy()
                .into_owned()
        }
    }
}

impl Drop for EmbeddedCompanion {
    fn drop(&mut self) {
        unsafe {
            idb_companion_destroy(self.handle);
        }
    }
}

// Thread safety: EmbeddedCompanion uses internal synchronization
unsafe impl Send for EmbeddedCompanion {}
unsafe impl Sync for EmbeddedCompanion {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_create_destroy() {
        let companion = EmbeddedCompanion::new();
        assert!(companion.is_ok());
    }
    
    #[test]
    fn test_version() {
        let version = EmbeddedCompanion::version();
        assert!(!version.is_empty());
    }
    
    #[test]
    fn test_error_string() {
        let error_msg = EmbeddedCompanion::error_string(IdbError::DeviceNotFound);
        assert_eq!(error_msg, "Device not found");
    }
}