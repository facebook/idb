/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;
@class FBApplicationLaunchStrategy;
@class FBDevice;
@class FBDeviceApplicationProcess;

/**
 A strategy for launching applications on a device.
 */
@interface FBDeviceApplicationLaunchStrategy : NSObject

#pragma mark Initializers

/**
 Creates a new Strategy.

 @param device the device to launch on.
 @param connection the connection to use.
 @param logger the logger to use.
 @return a new Application Launch Strategy.
 */
+ (instancetype)strategyWithDevice:(FBDevice *)device debugConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Launches an Application with the provided application launch configuration.

 @param launch the application launch configuration.
 @param remoteAppPath the remote path of the application.
 @return A future that resolves when successful, with the process identifier of the launched process.
 */
- (FBFuture<FBDeviceApplicationProcess *> *)launchApplication:(FBApplicationLaunchConfiguration *)launch remoteAppPath:(NSString *)remoteAppPath;

@end

NS_ASSUME_NONNULL_END
