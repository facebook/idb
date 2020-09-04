/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

/**
 File Commands related to a single target.
 This can be app or host-centric.
 */
@protocol FBFileContainer <NSObject>

/**
 Copy items to from the host, to the target.

 @note Performs a recursive copy
 @param paths Array of source paths on the host. May be Files and/or Directories.
 @param destinationPath the destination path within the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyPathsOnHost:(NSArray<NSURL *> *)paths toDestination:(NSString *)destinationPath;

/**
 Relocate a file from the target, to the host.

 @param containerPath the sub-path within the to copy out.
 @param destinationPath the path to copy in to.
 @return A future that resolves with the destination path when successful.
 */
- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath;

/**
 Create a directory inside the target.

 @param directoryPath the path to the directory to be created.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath;

/**
 Move a path inside the container

 @param sourcePath relative source path.
 @param destinationPath relative path where the data will be moved to
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)movePath:(NSString *)sourcePath toDestinationPath:(NSString *)destinationPath;

/**
 Remove paths inside the target.

 @param paths relative paths to the container where data resides
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths;

/**
 List directory within the target.

 @param path relative path to the container
 @return A future containing the list of entries that resolves when successful.
 */
- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
