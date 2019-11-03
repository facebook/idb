/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
#import <FBControlCore/FBFuture.h>

#import <sys/socket.h>
#import <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;
@protocol FBSocketConnectionManagerDelegate;

/**
 A wrapped socket-server, that manages the lifecycles of individual connections
 */
@interface FBSocketConnectionManager : NSObject

#pragma mark Initializers

/**
 Creates and returns a socket reader for the provided port and consumer.

 @param port the port to bind against.
 @param delegate the delegate to use.
 @return a new socket reader.
 */
+ (instancetype)socketReaderOnPort:(in_port_t)port delegate:(id<FBSocketConnectionManagerDelegate>)delegate;

#pragma mark Public

/**
 Create and Listen to the socket.

 @return A future when the socket listening has started.
 */
- (FBFuture<NSNull *> *)startListening;

/**
 Stop listening to the socket.

 @return A future when the socket listening has started.
 */
- (FBFuture<NSNull *> *)stopListening;

@end

/**
 A consumer of a socket.
 */
@protocol FBSocketConsumer <FBDataConsumer>

/**
 Called when a write end is available.

 @param writeBack a consumer to write back to.
 */
- (void)writeBackAvailable:(id<FBDataConsumer>)writeBack;

@end

/**
 The Delegate for the Socket Reader
 */
@protocol FBSocketConnectionManagerDelegate <NSObject>

/**
 Create a consumer for the provided client.

 @param clientAddress the client address.
 @return a consumer of the socket.
 */
- (id<FBSocketConsumer>)consumerWithClientAddress:(struct in6_addr)clientAddress;

@end

NS_ASSUME_NONNULL_END
