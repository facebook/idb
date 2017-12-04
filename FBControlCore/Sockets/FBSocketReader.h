/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileConsumer.h>
#import <FBControlCore/FBFuture.h>

#import <sys/socket.h>
#import <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@protocol FBSocketReaderDelegate;

/**
 A Reader of a Socket, passing input to a consumer.
 */
@interface FBSocketReader : NSObject

#pragma mark Initializers

/**
 Creates and returns a socket reader for the provided port and consumer.

 @param port the port to bind against.
 @param delegate the delegate to use.
 @return a new socket reader.
 */
+ (instancetype)socketReaderOnPort:(in_port_t)port delegate:(id<FBSocketReaderDelegate>)delegate;

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
@protocol FBSocketConsumer <FBFileConsumer>

/**
 Called when a write end is available.

 @param writeBack a consumer to write back to.
 */
- (void)writeBackAvailable:(id<FBFileConsumer>)writeBack;

@end

/**
 The Delegate for the Socket Reader
 */
@protocol FBSocketReaderDelegate <NSObject>

/**
 Create a consumer for the provided client.

 @param clientAddress the client address.
 @return a consumer of the socket.
 */
- (id<FBSocketConsumer>)consumerWithClientAddress:(struct in6_addr)clientAddress;

@end

NS_ASSUME_NONNULL_END
