/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the SpringBoardServices private API.
//
// SpringBoard owns the lock screen. Its lock screen service locks the device, and refuses a client
// without the private com.apple.springboard.lockDevice entitlement; the guest binary carries it and the
// simulator's SpringBoard honours it. The lock status is a plain MIG call that needs no entitlement.
//
// The framework is dlopen-loaded from the booted runtime root, its classes resolved with
// NSClassFromString and its functions with dlsym, so nothing here is referenced at link time.

#import <mach/mach.h>

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The framework's path inside the booted runtime root, for dlopen. */
#define FBAXPathSpringBoardServices "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"

/** A connection to SpringBoard's lock screen service. */
@interface SBSLockScreenService : NSObject

- (void)lockDeviceAnimated:(BOOL)animated withCompletion:(nullable void (^)(void))completion;

/** Must be called before the service is released: its `dealloc` raises otherwise. */
- (void)invalidate;

@end

/** `SBSSpringBoardServerPort()`: the send right MIG calls into SpringBoard go through. */
typedef mach_port_t (*FBSBSSpringBoardServerPort)(void);

/** `SBGetScreenLockStatus(port, &locked, &passcodeEnabled)`. */
typedef kern_return_t (*FBSBGetScreenLockStatus)(mach_port_t port, BOOL *locked, BOOL *passcodeEnabled);

NS_ASSUME_NONNULL_END
