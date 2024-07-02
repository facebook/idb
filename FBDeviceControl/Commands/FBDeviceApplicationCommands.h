/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
 Instantiates the Commands instance.

 @param target the target to use.
 @return a new instance of the Command.
 */
+ (instancetype)commandsWithTarget:(FBDevice *)target;

/**
 Installs application at given path on the host using a shadow dir on the host to only install changed files.

 @param path the file path of the Application Bundle on the host.
 @param shadowDir directory on the host that is used for the shadow copy.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)deltaInstallApplicationWithPath:(NSString *)path andShadowDirectory:(NSString *)shadowDir;

@end

NS_ASSUME_NONNULL_END
