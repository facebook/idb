/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import "FBIDBEmbeddedServer.h"
#import "FBIDBCommandExecutor.h"
#import "idb_direct.h"

// HID API compatibility macros
#if __has_include(<FBSimulatorControl/FBSimulatorHID.h>)
#import <FBSimulatorControl/FBSimulatorHID.h>
// Check if performHIDEvent: exists (Xcode 16+)
#define HAS_PERFORM_HID_EVENT ([FBSimulatorHID instancesRespondToSelector:@selector(performHIDEvent:)])
#else
#define HAS_PERFORM_HID_EVENT NO
#endif

// Macro to send HID events with API compatibility
#define FBIDB_SEND_HID(hid, event) \
  (HAS_PERFORM_HID_EVENT ? \
    [(hid) performHIDEvent:(event)] : \
    [(hid) handleEvent:(event)])


// Static variables for state management
static FBIDBEmbeddedServer *_server = nil;
static FBSimulatorSet *_simulatorSet = nil;
static FBSimulator *_bootedSimulator = nil;
static id<FBControlCoreLogger> _logger = nil;

#pragma mark - Initialization

idb_error_t idb_initialize(void) {
  @autoreleasepool {
    if (_server) {
      NSLog(@"idb_direct: Already initialized");
      return IDB_SUCCESS;
    }
    
    // Initialize logger
    _logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"idb_direct"];
    
    // Create simulator set
    NSError *error = nil;
    _simulatorSet = [FBSimulatorSet defaultSetWithLogger:_logger error:&error];
    if (!_simulatorSet) {
      NSLog(@"idb_direct: Failed to create simulator set: %@", error);
      return IDB_ERROR_INITIALIZATION_FAILED;
    }
    
    // Find first booted simulator
    NSArray<FBSimulator *> *simulators = [_simulatorSet query:[FBiOSTargetQuery queryWithState:FBiOSTargetStateBooted]];
    if (simulators.count == 0) {
      NSLog(@"idb_direct: No booted simulators found");
      return IDB_ERROR_NO_BOOTED_SIMULATOR;
    }
    
    _bootedSimulator = simulators.firstObject;
    NSLog(@"idb_direct: Found booted simulator: %@", _bootedSimulator.udid);
    
    // Create embedded server
    _server = [FBIDBEmbeddedServer embeddedServerWithTarget:_bootedSimulator
                                                     logger:_logger
                                                      error:&error];
    if (!_server) {
      NSLog(@"idb_direct: Failed to create embedded server: %@", error);
      return IDB_ERROR_INITIALIZATION_FAILED;
    }
    
    // Start the server
    if (![_server startWithError:&error]) {
      NSLog(@"idb_direct: Failed to start embedded server: %@", error);
      _server = nil;
      return IDB_ERROR_INITIALIZATION_FAILED;
    }
    
    NSLog(@"idb_direct: Successfully initialized with simulator: %@", _bootedSimulator.udid);
    return IDB_SUCCESS;
  }
}

#pragma mark - HID Operations

idb_error_t idb_tap(double x, double y) {
  @autoreleasepool {
    if (!_server || !_bootedSimulator) {
      NSLog(@"idb_direct: Not initialized");
      return IDB_ERROR_NOT_INITIALIZED;
    }
    
    NSError *error = nil;
    
    // Get HID interface
    FBSimulatorHID *hid = [_bootedSimulator hid];
    if (!hid) {
      NSLog(@"idb_direct: No HID interface available");
      return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Create tap event
    FBSimulatorHIDEvent *event = [FBSimulatorHIDEvent tapAtX:x y:y];
    
    // Send event with compatibility wrapper
    FBFuture *future = FBIDB_SEND_HID(hid, event);
    
    // Wait for completion
    if (![FBIDBWait awaitFuture:future timeout:5.0 error:&error]) {
      NSLog(@"idb_direct: Tap failed: %@", error);
      return IDB_ERROR_OPERATION_FAILED;
    }
    
    NSLog(@"idb_direct: Tap at (%.1f, %.1f) successful", x, y);
    return IDB_SUCCESS;
  }
}

#pragma mark - Screenshot

idb_error_t idb_screenshot(idb_screenshot_callback callback, void *context) {
  @autoreleasepool {
    if (!_server || !_bootedSimulator) {
      NSLog(@"idb_direct: Not initialized");
      return IDB_ERROR_NOT_INITIALIZED;
    }
    
    NSError *error = nil;
    
    // Take screenshot using command executor
    FBFuture<NSData *> *future = [[_server.commandExecutor take_screenshot:FBScreenshotFormatPNG] 
                                  onQueue:_bootedSimulator.workQueue map:^id(id result) {
      return result;
    }];
    
    NSData *screenshotData = [FBIDBWait awaitFuture:future timeout:10.0 error:&error];
    if (!screenshotData) {
      NSLog(@"idb_direct: Screenshot failed: %@", error);
      return IDB_ERROR_OPERATION_FAILED;
    }
    
    // Call the callback with the data
    if (callback) {
      callback(screenshotData.bytes, screenshotData.length, context);
    }
    
    NSLog(@"idb_direct: Screenshot captured, size: %lu bytes", (unsigned long)screenshotData.length);
    return IDB_SUCCESS;
  }
}

#pragma mark - Shutdown

idb_error_t idb_shutdown(void) {
  @autoreleasepool {
    if (!_server) {
      NSLog(@"idb_direct: Not initialized");
      return IDB_ERROR_NOT_INITIALIZED;
    }
    
    [_server shutdown];
    _server = nil;
    _bootedSimulator = nil;
    _simulatorSet = nil;
    _logger = nil;
    
    NSLog(@"idb_direct: Shutdown complete");
    return IDB_SUCCESS;
  }
}

#pragma mark - Error Handling

const char* idb_error_string(idb_error_t error) {
  switch (error) {
    case IDB_SUCCESS:
      return "Success";
    case IDB_ERROR_NOT_INITIALIZED:
      return "Not initialized";
    case IDB_ERROR_INITIALIZATION_FAILED:
      return "Initialization failed";
    case IDB_ERROR_NO_BOOTED_SIMULATOR:
      return "No booted simulator found";
    case IDB_ERROR_INVALID_ARGUMENTS:
      return "Invalid arguments";
    case IDB_ERROR_OPERATION_FAILED:
      return "Operation failed";
    default:
      return "Unknown error";
  }
}