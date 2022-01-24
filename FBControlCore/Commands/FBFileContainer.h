/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An enumeration representing the existing file containers.
 */
typedef NSString *FBFileContainerKind NS_STRING_ENUM;
extern FBFileContainerKind const FBFileContainerKindApplication;
extern FBFileContainerKind const FBFileContainerKindAuxillary;
extern FBFileContainerKind const FBFileContainerKindCrashes;
extern FBFileContainerKind const FBFileContainerKindDiskImages;
extern FBFileContainerKind const FBFileContainerKindGroup;
extern FBFileContainerKind const FBFileContainerKindMDMProfiles;
extern FBFileContainerKind const FBFileContainerKindMedia;
extern FBFileContainerKind const FBFileContainerKindProvisioningProfiles;
extern FBFileContainerKind const FBFileContainerKindRoot;
extern FBFileContainerKind const FBFileContainerKindSpringboardIcons;
extern FBFileContainerKind const FBFileContainerKindSymbols;
extern FBFileContainerKind const FBFileContainerKindWallpaper;

@protocol FBDataConsumer;
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
- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath;

/**
 Copy a path from inside the container, to the host.

 @param sourcePath the source path, relative to the root of the container. May be Files and/or Directories.
 @param destinationPath the destination path on the host.
 @return A future that resolves with the destination path when successful.
 */
- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath;

/**
 Tails the contents of a file path inside the container, to a data consumer.
 
 @param path the source path to tail, relative to the root of the container. Must be a file
 @param consumer the consumer to write to.
 @return a Future that resolves with a Future when the tailing has completed. The wrapped future can be cancelled to end the tailing operation.
 */
- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer;

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
 An abstraction over a file. The file can be local to the host, or remote.
 */
@protocol FBContainedFile <NSObject>

/**
 Removes a file path.
 If the path is a directory, the entire directory is removed and all contents, recursively.

 @param error an error out for any error that occurs.
 @return YES on success, NO otherwise.
 */
- (BOOL)removeItemWithError:(NSError **)error;

/**
 List the contents of a path.

 @param error an error out for any error that occurs.
 @return an array of strings representing the directory contents.
 */
- (nullable NSArray<NSString *> *)contentsOfDirectoryWithError:(NSError **)error;

/**
 Obtains the contents of the contained file.

 @param error an error out for any error that occurs.
 @return Data for the file, or an nil on error.
 */
- (nullable NSData *)contentsOfFileWithError:(NSError **)error;

/**
 Creates a directory at the given path.

 @param error an error out for any error that occurs.
 @return YES on success, NO otherwise.
 */
- (BOOL)createDirectoryWithError:(NSError **)error;

/**
 Checks whether the path exists, optionally providing information about whether the path is a regular file or directory.

 @param isDirectoryOut an outparam for indicating if the path represents a directory.
 @return YES if exists, NO otherwise.
 */
- (BOOL)fileExistsIsDirectory:(BOOL *)isDirectoryOut;

/**
 Moves the receiver to the provided destination file.

 @param destination the destination to move to.
 @param error an error out for any error that occurs.
 */
- (BOOL)moveTo:(id<FBContainedFile>)destination error:(NSError **)error;

/**
 Replaces the contents of the wrapped file with the provided path on the host filesystem.

 @param path the path to pull contents from.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)populateWithContentsOfHostPath:(NSString *)path error:(NSError **)error;

/**
 Replaces provided path on the host filesystem with the contents of the wrapped file.

 @param path the path to push contents to.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)populateHostPathWithContents:(NSString *)path error:(NSError **)error;

/**
 Constructs a new contained file by appending a path component.

 @param component the component to add.
 @param error an error out if the path is invalid.
 @return the new contained file.
 */
- (id<FBContainedFile>)fileByAppendingPathComponent:(NSString *)component error:(NSError **)error;

/**
 The host path corresponding to this file, if any.
 If the file is remote, this will be nil
 */
@property (nonatomic, copy, nullable, readonly) NSString *pathOnHostFileSystem;

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

/**
 A file container that relative to a path on the host.
 
 @param basePath the base path to use.
 @return a File Container implementation
 */
+ (id<FBFileContainer>)fileContainerForBasePath:(NSString *)basePath;

/**
 A file container that relative to a path on the host.
 
 @param pathMapping the mapped base paths.
 @return a File Container implementation
 */
+ (id<FBFileContainer>)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping;

@end

NS_ASSUME_NONNULL_END
