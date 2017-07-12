/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorBootConfiguration.h>

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

@interface FBSimulatorBootConfiguration (Helpers)

/**
 Whether the reciever represents a configuration that should call SimDevice booting directly.
 */
- (BOOL)shouldUseDirectLaunch;

/**
 Whether the reciever represents a configuration that should connect an FBFramebuffer on boot.
 */
- (BOOL)shouldConnectFramebuffer;

/**
 Whether the reciever represents a configuration that should boot via the NSWorkspace Application Launch API.
 */
- (BOOL)shouldLaunchViaWorkspace;

/**
 Whether the reciever represents a configuration that should connect the Bridge on Launch.
 */
- (BOOL)shouldConnectBridge;

@end

NS_ASSUME_NONNULL_END
