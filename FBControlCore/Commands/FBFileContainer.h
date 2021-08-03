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
 File Operations related to a single "container"
 These containers are obtained from implementors of FBFileCommands.
 */
@protocol FBFileContainer <NSObject>

/**
 Copy a path from the host, to inside the container.

 @note Performs a recursive copy
 @param sourcePath The source path on the host. May be Files and/or Directories.
 @param destinationPath the destination path to copy to, relative to the root of the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath;

/**
 Copy a path from inside the container, to the host.

 @param containerPath the source path, relative to the root of the container. May be Files and/or Directories.
 @param destinationPath the destination path on the host.
 @return A future that resolves with the destination path when successful.
 */
- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath;

/**
 Create a directory inside the container.

 @param directoryPath the path to the directory to be created within the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath;

/**
 Move a path inside the container.

 @param sourcePath the source path, relative to the root of the container.
 @param destinationPath the destination path, relative to the root of the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath;

/**
 Remove a path inside the container.

 @param path the path to remove, relative to the root of the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)remove:(NSString *)path;

/**
 List directory within the container.

 @param path the path to list, relative to the root of the container.
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
