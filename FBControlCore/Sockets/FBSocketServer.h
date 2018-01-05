/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

@end

/**
 The Delegate for the Server.
 */
@protocol FBSocketServerDelegate <NSObject>

/**
 Called when the socket server has a new client connected.
 The File Handle return will close on deallocation so it is up to consumers to retain it.

 @param server the socket server.
 @param address the IP Address of the connected client.
 @param fileHandle the file handle of the connected socket.
 */
- (void)socketServer:(FBSocketServer *)server clientConnected:(struct in6_addr)address handle:(NSFileHandle *)fileHandle;

/**
 The Queue on which the Delegate will be called.
 This may be a serial or a concurrent queue.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END
