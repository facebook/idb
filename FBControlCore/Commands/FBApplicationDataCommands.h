/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
 Copy items to from the host, to Application Data Container.

 @note Performs a recursive copy
 @param paths Array of source paths on the host. May be Files and/or Directories.
 @param destinationPath the destination path within the container.
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyPathsOnHost:(NSArray<NSURL *> *)paths toDestination:(NSString *)destinationPath insideContainerOfApplication:(NSString *)bundleID;

/**
 Relocate a file from the Application Data Container, to the host.

 @param containerPath the sub-path within the to copy out.
 @param destinationPath the path to copy in to.
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves with the destination path when successful.
 */
- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath fromContainerOfApplication:(NSString *)bundleID;

/**
 Create a directory inside the Application Data Container.

 @param directoryPath the path to the directory to be created.
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath insideContainerOfApplication:(NSString *)bundleID;

/**
 Move paths inside the Application Data Container.

 @param originPaths relative paths to the container where data resides
 @param destinationPath relative path where the data will be moved to
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toDestinationPath:(NSString *)destinationPath insideContainerOfApplication:(NSString *)bundleID;

/**
 Remove paths inside the Application Data Container.

 @param paths relative paths to the container where data resides
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths insideContainerOfApplication:(NSString *)bundleID;

/**
 List directory within the container

 @param path relative path to the container
 @param bundleID the Bundle Identifier of the Container.
 @return A future containing the list of entries that resolves when successful.
 */
- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path insideContainerOfApplication:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
