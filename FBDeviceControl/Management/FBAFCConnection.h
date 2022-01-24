/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBFileContainer.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;
@protocol FBControlCoreLogger;

/**
 An Object wrapper for an Apple File Conduit handle.
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

#pragma mark Public

/**
 Obtains a contained file for the provided path.

 @param path the path to obtained a file path for.
 @return a contained file for the path
 */
- (id<FBContainedFile>)containedFileForPath:(NSString *)path;

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

/**
 The contained file for the root of the connection.
 */
@property (nonatomic, strong, readonly) id<FBContainedFile> rootContainedFile;

@end

NS_ASSUME_NONNULL_END
