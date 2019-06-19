/**
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
 Relocate Data inside the Application Data Container.

 @param source the Source Path. May be a File or Directory.
 @param bundleID the Bundle Identifier of the Container.
 @param containerPath the sub-path within the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyDataAtPath:(NSString *)source toContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath;

/**
 Copy items to the Application Data Container.

 @param paths Array of source paths. May be Files and/or Directories.
 @param containerPath the destination path within the container.
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.

 @note Performs a recursive copy
 */
- (FBFuture<NSNull *> *)copyItemsAtURLs:(NSArray<NSURL *> *)paths toContainerPath:(NSString *)containerPath inBundleID:(NSString *)bundleID;

/**
 Relocate Data inside the Application Data Container.

 @param bundleID the Bundle Identifier of the Container.
 @param containerPath the sub-path within the to copy out.
 @param destinationPath the path to copy in to.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath;

/**
 Create Directory inside the Application Data Container.

 @param directoryPath the path to the directory to be created.
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath inContainerOfApplication:(NSString *)bundleID;

/**
 Move data within the container to a different path
 @param originPaths relative paths to the container where data resides
 @param destinationPath relative path where the data will be moved to
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID;

/**
 Remove path within the container

 @param paths relative paths to the container where data resides
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths inContainerOfApplication:(NSString *)bundleID;

/**
 List directory within the container
 @param path relative path to the container
 @param bundleID the Bundle Identifier of the Container.
 @return A future containing the list of entries that resolves when successful.
 */
- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path inContainerOfApplication:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
