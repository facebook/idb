/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBDevice;

/**
 An Implementation of FBDeviceEraseCommands for Devices
 */
@interface FBDeviceEraseCommands : NSObject <FBEraseCommands>

// FBiOSTargetCommand / FBEraseCommands (Swift protocol members declared for visibility)
+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target;
- (nonnull FBFuture<NSNull *> *)erase;

@end
