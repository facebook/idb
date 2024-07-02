/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

#import <sys/socket.h>
#import <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBSocketServerDelegate;

/**
 A Generic Socket Server.
 */
@interface FBSocketServer : NSObject

#pragma mark Initializers

/**
 Creates and returns a socket reader for the provided port and consumer.

 @param port the port to bind against.
 @param delegate the delegate to use.
 @return a new socket reader.
 */
+ (instancetype)socketServerOnPort:(in_port_t)port delegate:(id<FBSocketServerDelegate>)delegate;

#pragma mark Properties

/**
 The Port the Server is Bound on
 */
@property (nonatomic, assign, readonly) in_port_t port;

#pragma mark Public Methods

/**
 Create and Listen to the socket.

 @return A future that resolves when listening has started.
 */
- (FBFuture<NSNull *> *)startListening;

/**
 Stop listening to the socket

 @return A future that resolves when listening has ended.
 */
- (FBFuture<NSNull *> *)stopListening;

/**
 Starts the socket server, managed by a context manager

 @return a FBFutureContext that will stop listening when the context is torn down.
 */
- (FBFutureContext<NSNull *> *)startListeningContext;

@end

/**
 The Delegate for the Server.
 */
@protocol FBSocketServerDelegate <NSObject>

/**
 Called when the socket server has a new client connected.
 The File Descriptor will not be automatically be closed, so it's up to implementors to ensure that this happens so file descriptors do not leak.
 If you wish to reject the connection, close the file handle immediately.

 @param server the socket server.
 @param address the IP Address of the connected client.
 @param fileDescriptor the file descriptor of the connected socket.
 */
- (void)socketServer:(FBSocketServer *)server clientConnected:(struct in6_addr)address fileDescriptor:(int)fileDescriptor;

/**
 The Queue on which the Delegate will be called.
 This may be a serial or a concurrent queue.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END
