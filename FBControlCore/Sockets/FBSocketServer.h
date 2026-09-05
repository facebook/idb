/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <netinet/in.h>
#import <sys/socket.h>

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

@protocol FBSocketServerDelegate;

/**
 A Generic Socket Server.
 */
@interface FBSocketServer : NSObject

#pragma mark Initializers

/**
 Creates a socket server for the provided port and delegate.

 @param port the port to bind against.
 @param delegate the delegate to use.
 @return a new socket server.
 */
+ (nonnull instancetype)socketServerOnPort:(in_port_t)port delegate:(nonnull id<FBSocketServerDelegate>)delegate;

#pragma mark Properties

/**
 The Port the Server is Bound on
 */
@property (nonatomic, readonly, assign) in_port_t port;

#pragma mark Public Methods

/**
 Create and Listen to the socket.

 @return A future that resolves when listening has started.
 */
- (nonnull FBFuture<NSNull *> *)startListening;

/**
 Stop listening to the socket

 @return A future that resolves when listening has ended.
 */
- (nonnull FBFuture<NSNull *> *)stopListening;

/**
 Listens until the returned context is torn down.
 */
- (nonnull FBFutureContext<NSNull *> *)startListeningContext;

@end
