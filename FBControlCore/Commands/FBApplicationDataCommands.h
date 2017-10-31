/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBInstalledApplication;

/**
 Defines an interface for interacting with the Data Container of Applications.
 */
@protocol FBApplicationDataCommands <NSObject, FBiOSTargetCommand>

/**
 Relocate Data inside the Application Data Container.

 @param source the Source Path. May be a File or Directory.
 @param bundleID the Bundle Identifier of the Container.
 @param containerPath the sub-path within the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyDataAtPath:(NSString *)source toContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath;

/**
 Relocate Data inside the Application Data Container.

 @param bundleID the Bundle Identifier of the Container.
 @param containerPath the sub-path within the to copy out.
 @param destinationPath the path to copy in to.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath;

@end

NS_ASSUME_NONNULL_END
