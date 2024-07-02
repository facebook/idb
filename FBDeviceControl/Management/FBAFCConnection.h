/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;
@protocol FBControlCoreLogger;

/**
 An Object wrapper for an Apple File Conduit handle/
 */
@interface FBAFCConnection : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param connection the wrapped pointer value.
 @param calls the calls to use.
 @param logger the logger to use.
 @return a new FBAFConnection Instance.
 */
- (instancetype)initWithConnection:(AFCConnectionRef)connection calls:(AFCCalls)calls logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Constructs an FBAFCConnection from a Service Connection and tears it down after.

 @param serviceConnection the connection to use.
 @param calls the calls to use.
 @param logger the logger to use.
 @param queue the logger to use.
 @return an FBAFCConnection instance.
 */
+ (FBFutureContext<FBAFCConnection *> *)afcFromServiceConnection:(FBAMDServiceConnection *)serviceConnection calls:(AFCCalls)calls logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue;

#pragma mark Public Methods

/**
 Copies an item at the provided url into an application container.
 The source file can represent a file or a directory.

 @param hostPath the source file on the host.
 @param containerPath the file path relative to the application container.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)copyFromHost:(NSString *)hostPath toContainerPath:(NSString *)containerPath error:(NSError **)error;

/**
 Creates a Directory.

 @param path the path to create.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)createDirectory:(NSString *)path error:(NSError **)error;

/**
 Get the contents of a directory.

 @param path the path to locate.
 @param error an error out for any occurs
 @return the contents of the directory.
 */
- (nullable NSArray<NSString *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error;

/**
 Get the contents of a file.

 @param path the path to read.
 @param error an error out for any occurs.
 @return the data for the file.
 */
- (nullable NSData *)contentsOfPath:(NSString *)path error:(NSError **)error;

/**
 Removes a path.

 @param path the path to remove.
 @param recursively YES to recurse, NO otherwise.
 @param error an error out for any occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)removePath:(NSString *)path recursively:(BOOL)recursively error:(NSError **)error;

/**
 Renames a path.

 @param path the path to rename
 @param destination the destination path.
 @param error an error out for any occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)renamePath:(NSString *)path destination:(NSString *)destination error:(NSError **)error;

/**
 Close the connection.
 The connection should not be used after this.

 @param error an error out for any error that occurs.
 @return YES if succesful, NO otherwise.
 */
- (BOOL)closeWithError:(NSError **)error;

#pragma mark Properties

/**
 The wrapped 'Apple File Conduit'.
 */
@property (nonatomic, assign, readonly, nullable) AFCConnectionRef connection;

/**
 The Calls to use.
 */
@property (nonatomic, assign, readonly) AFCCalls calls;

/**
 The logger to use
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The Default Calls.
 */
@property (nonatomic, assign, readonly, class) AFCCalls defaultCalls;

@end

NS_ASSUME_NONNULL_END
