/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBAMDevice+Private.h"

NS_ASSUME_NONNULL_BEGIN

@class FBServiceConnectionClient;

@protocol FBControlCoreLogger;

/**
 The Connection Reference as is typically passed around between functions.
 */
typedef CFTypeRef AMDServiceConnectionRef;

/**
 Wraps the AMDServiceConnection.
 */
@interface FBAMDServiceConnection : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param connection the connection to use.
 @param device the device to use.
 @param calls the calls to use.
 @param logger the logger to use.
 @return a FBAMDServiceConnection instance.
 */
- (instancetype)initWithServiceConnection:(AMDServiceConnectionRef)connection device:(AMDeviceRef)device calls:(AMDCalls)calls logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public

/**
 Synchronously send bytes on the connection.

 @param size the length in bytes of data to receive.
 @param error an error out for any error that occurs.
 @return YES if the bytes were sent, NO otherwise.
 */
- (BOOL)send:(NSData *)data error:(NSError **)error;

/**
 Synchronously receive bytes from the connection.

 @param size the length in bytes of data to receive.
 @param error an error out for any error that occurs.
 @return the data.
 */
- (NSData *)receive:(size_t)size error:(NSError **)error;

/**
 Invalidates the Service connection.
 After this is called, this object is no longer valid.

 @param error an error out for any error that occurs.
 @return YES is succesful, NO otherwise.
 */
- (BOOL)invalidateWithError:(NSError **)error;

/**
 Build a service connection client, returning it in an FBFutureContext.

 @param logger the logger to use.
 @param queue the queue to execute on
 @return an FBFutureContext wrapping the client.
 */
- (FBFutureContext<FBServiceConnectionClient *> *)makeClientWithLogger:(id<FBControlCoreLogger>)logger  queue:(dispatch_queue_t)queue;

#pragma mark Properties

/**
 The Wrapped Connection.
 */
@property (nonatomic, assign, readonly, nullable) AMDServiceConnectionRef connection;

/**
 The Device to use.
 */
@property (nonatomic, assign, readonly) AMDeviceRef device;

/**
 The Calls to use.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The Logger to use.
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The socket for the connection.
 */
@property (nonatomic, assign, readonly) int socket;

/**
 The Secure IO Context.
 */
@property (nonatomic, assign, readonly) BOOL secureIOContext;

@end

NS_ASSUME_NONNULL_END
