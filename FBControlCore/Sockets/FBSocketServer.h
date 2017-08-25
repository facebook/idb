/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <sys/socket.h>
#import <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBSocketServerDelegate;

/**
 A Generic Socket Server.
 */
@interface FBSocketServer : NSObject

@property (nonatomic, assign, readonly) in_port_t port;

/**
 Creates and returns a socket reader for the provided port and consumer.

 @param port the port to bind against.
 @param delegate the delegate to use.
 @return a new socket reader.
 */
+ (instancetype)socketServerOnPort:(in_port_t)port delegate:(id<FBSocketServerDelegate>)delegate;

/**
 Create and Listen to the socket.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startListeningWithError:(NSError **)error;

/**
 Stop listening to the socket

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)stopListeningWithError:(NSError **)error;

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
 The Queue to call the delegate on.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END
