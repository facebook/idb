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

/**
 The xctest.xctestrun properties for a test launch.

 @param testLaunch the test launch to base off.
 @return the xctest.xctestrun properties.
 */
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch;

@end

NS_ASSUME_NONNULL_END
