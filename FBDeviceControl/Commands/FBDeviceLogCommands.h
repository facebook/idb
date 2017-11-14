/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 The Termination Handle Type for a log tail.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeLogTail;

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 An implementation of Log Commands for Devices.
 */
@interface FBDeviceLogCommands : NSObject <FBLogCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
