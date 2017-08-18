/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@class FBDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 An implementation of FBXCTestCommands, for Devices.
 */
@interface FBDeviceXCTestCommands : NSObject <FBXCTestCommands>

/**
 The Designated Initializer.

 @param device the Device.
 @return a new Device Commands Instance.
 */
+ (instancetype)commandsWithDevice:(FBDevice *)device;

@end

NS_ASSUME_NONNULL_END
