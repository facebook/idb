/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 A Service Connection Client.
 This can be used to build clients of multiple protocols.
 */
@interface FBServiceConnectionClient : NSObject

#pragma mark Initializers

/**
 Makes a FBServiceConnectionClient from an existing service connection.
 The provided client is an FBFutureContext. This is because the reading and writing of the service connection needs to be torn down before the service.

 @param connection the service connection connection to use.
 @param queue the queue to execute on
 @param logger the logger to log to.
 @return a Future wrapping the FBServiceConnectionClient Client.
 */
+ (FBFutureContext<FBServiceConnectionClient *> *)clientForServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue  logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Sends a packet, resolving when a response packet has been received.

 @param payload the payload to send
 @param terminator the terminator to wait for
 @return a Future that resolves with the packet response.
 */
- (FBFuture<NSData *> *)send:(NSData *)payload terminator:(NSData *)terminator;

/**
 Sends a packet.

 @param payload the payload to use.
 */
- (void)sendRaw:(NSData *)payload;

#pragma mark Properties

/**
 The queue to use.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The command buffer
 */
@property (nonatomic, strong, readonly) id<FBNotifyingBuffer> buffer;


@end

NS_ASSUME_NONNULL_END
