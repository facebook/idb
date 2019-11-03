/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;
@class FBGDBClient;

/**
 A FBLaunchedProcess that wraps an appliation launch on a device.
 */
@interface FBDeviceApplicationProcess : NSObject <FBLaunchedProcess>

#pragma mark Initializers

/**
 The designated initializer.

 @param device the device to use.
 @param configuration the app launch configuration.
 @param gdbClient the gdb client to use.
 @param stdOut the stdout to redirect to.
 @param stdErr the stderr to redirect to.
 @param launchFuture a future that resolves with the process id when launched.
 @return a future that resolves with a FBLaunchedProcess instance.
 */
+ (FBFuture<FBDeviceApplicationProcess *> *)processWithDevice:(FBDevice *)device configuration:(FBApplicationLaunchConfiguration *)configuration gdbClient:(FBGDBClient *)gdbClient stdOut:(id<FBProcessOutput>)stdOut stdErr:(id<FBProcessOutput>)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture;

@end

NS_ASSUME_NONNULL_END
