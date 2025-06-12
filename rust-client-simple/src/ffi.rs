#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

use std::ffi::{CStr, CString};
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

fn check_result(err: idb_error_t) -> Result<(), IdbError> {
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

pub struct IdbDirect {
    connected: bool,
}

impl IdbDirect {
    pub fn new() -> Result<Self, IdbError> {
        unsafe {
            check_result(idb_initialize())?;
        }
        Ok(Self { connected: false })
    }
    
    pub fn connect_simulator(&mut self, udid: &str) -> Result<(), IdbError> {
        let c_udid = CString::new(udid).map_err(|_| IdbError::InvalidParameter)?;
        unsafe {
            check_result(idb_connect_target(c_udid.as_ptr(), idb_target_type_t_IDB_TARGET_SIMULATOR))?;
        }
        self.connected = true;
        Ok(())
    }
    
    pub fn tap(&self, x: f64, y: f64) -> Result<(), IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        unsafe {
            check_result(idb_tap(x, y))?;
        }
        Ok(())
    }
    
    pub fn touch_down(&self, x: f64, y: f64) -> Result<(), IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        unsafe {
            check_result(idb_touch_event(idb_touch_type_t_IDB_TOUCH_DOWN, x, y))?;
        }
        Ok(())
    }
    
    pub fn touch_up(&self, x: f64, y: f64) -> Result<(), IdbError> {
        if !self.connected {
            return Err(IdbError::DeviceNotFound);
        }
        unsafe {
            check_result(idb_touch_event(idb_touch_type_t_IDB_TOUCH_UP, x, y))?;
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
            check_result(idb_take_screenshot(&mut screenshot))?;
            
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
            check_result(idb_swipe(from_point, to_point, duration_secs))?;
        }
        Ok(())
    }
    
    pub fn disconnect(&mut self) -> Result<(), IdbError> {
        if self.connected {
            unsafe {
                check_result(idb_disconnect_target())?;
            }
            self.connected = false;
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