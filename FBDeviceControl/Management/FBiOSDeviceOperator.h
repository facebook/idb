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

#import <XCTestBootstrap/FBDeviceOperator.h>

@class FBDevice;

/**
 A 'Device Operator' Implementation for providing the necessary functionality to XCTestBoostrap for Physical Devices.
 Uses the Xcode Frameworks DVTFoundation and IDEiOSSupportCore.ideplugin to control a DVTiOSDevice instance directly.
 */
@interface FBiOSDeviceOperator : NSObject <FBDeviceOperator>

#pragma mark Initializers

/**
 Creates a new Device Operator for the provided Device.

 @param device the Device to create the Operator for.
 @return a new FBiOSDeviceOperator instance.
 */
+ (instancetype)forDevice:(FBDevice *)device;

#pragma mark Public Methods

/**
 Launches an Application with the provided Application Launch Configuration.

 @param configuration the Application Launch Configuration to use.
 @return A future that resolves when successful, with the process identifier of the launched process.
 */
- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration;

/**
 Kills application with the given bundle identifier.

 @param bundleID bundle ID of installed application
 @return A future that resolves successfully if the bundle was running and is now killed.
 */
- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID;

@end
