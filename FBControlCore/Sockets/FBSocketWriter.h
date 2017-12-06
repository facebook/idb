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

@protocol FBSocketConsumer;

/**
 A Writer for a Socket.
 */
@interface FBSocketWriter : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param host the host to write to.
 @param port the port to write to.
 @param consumer the consumer.
 @return a new Socket Writer Instance.
 */
+ (instancetype)writerForHost:(NSString *)host port:(in_port_t)port consumer:(id<FBSocketConsumer>)consumer;

#pragma mark Public Methods

/**
 Start writing to the socket.

 @return A future that resolves when writing has started.
 */
- (FBFuture<NSNull *> *)startWriting;

/**
 Stop writing to the socket.

 @return A future that resolves when writing has started.
 */
- (FBFuture<NSNull *> *)stopWriting;

@end

NS_ASSUME_NONNULL_END
