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
 An implementation of Log Commands for Devices.
 */
@interface FBDeviceLogCommands : NSObject <FBLogCommands, FBiOSTargetCommand>

@end
