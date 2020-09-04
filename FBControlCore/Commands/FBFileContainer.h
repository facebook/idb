/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBProvisioningProfileCommands;

/**
 File Commands related to a single target.
 This can be app or host-centric.
 */
@protocol FBFileContainer <NSObject>

/**
 Copy items to from the host, to the target.

 @note Performs a recursive copy
 @param sourcePath The source path on the host. May be Files and/or Directories.
 @param destinationPath the destination path within the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyPathOnHost:(NSURL *)sourcePath toDestination:(NSString *)destinationPath;

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
 Remove a path inside the target.

 @param path relative path inside the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)removePath:(NSString *)path;

/**
 List directory within the target.

 @param path relative path to the container
 @return A future containing the list of entries that resolves when successful.
 */
- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path;

@end

/**
 Implementations of File Commands.
 */
@interface FBFileContainer : NSObject

/**
 A file container for a Provisioning Profile Commands implementation.

 @param commands the FBProvisioningProfileCommands instance to wrap.
 @param queue the queue to do work on.
 @return a File Container implementation.
 */
+ (id<FBFileContainer>)fileContainerForProvisioningProfileCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
