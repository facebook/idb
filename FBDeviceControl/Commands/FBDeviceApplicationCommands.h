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

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 An Implementation of FBApplicationCommands for Devices
 */
@interface FBDeviceApplicationCommands : NSObject <FBApplicationCommands>

/**
 The Designated Initializers.

 @param device the Device to use.
 @return an implemented of FBApplicationCommands.
 */
+ (instancetype)commandsWithDevice:(FBDevice *)device;

@end

NS_ASSUME_NONNULL_END
