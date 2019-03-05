/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 A GDB Client implementation.
 Some of the information here comes from the gdb remote protocol spec from the llvm project https://github.com/llvm-mirror/lldb/blob/master/docs/lldb-gdb-remote.txt
 There's also more information in the GDB protocol spec https://sourceware.org/gdb/onlinedocs/gdb/General-Query-Packets.html
 */
@interface FBGDBClient : NSObject

#pragma mark Initializers

/**
 Makes a GDBClient from an existing service connection to the debugserver.

 @param connection the debugserver connection to use.
 @param queue the queue to serialize work on.
 @param logger the logger to log to.
 @return a Future wrapping the GDB Client.
 */
+ (FBFuture<FBGDBClient *> *)clientForServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Sets the environment packet.

 @param environment the environment variables to send.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)sendEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/**
 Sets the arguments packet.

 @param arguments the arguments to set.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)sendArguments:(NSArray<NSString *> *)arguments;

/**
 Launches the application.

 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)launchSuccess;

/**
 Continues execution
 */
- (void)sendContinue;

/**
 Gets the process identifer from the process info packet.

 @return a Future that resolves when successful.
 */
- (FBFuture<NSNumber *> *)processInfo;

/**
 Disables ACKs in the protocol.

 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)noAckMode;

@end

NS_ASSUME_NONNULL_END
