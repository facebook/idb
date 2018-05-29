// Copyright 2004-present Facebook. All Rights Reserved.

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

#import <FBDeviceControl/FBAFCConnection.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An implementation of FBApplicationDataCommands for Devices
 */
@interface FBDeviceApplicationDataCommands : NSObject <FBApplicationDataCommands, FBiOSTargetCommand>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to use.
 @param afcCalls the calls to use.
 @return a new FBDeviceApplicationDataCommands instance.
 */
+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target afcCalls:(AFCCalls)afcCalls;

@end

NS_ASSUME_NONNULL_END
