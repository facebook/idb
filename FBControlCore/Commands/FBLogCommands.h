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
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;

/**
 Commands for obtaining logs.
 */
@protocol FBLogCommands <NSObject, FBiOSTargetCommand>

/**
 Starts tailing the log of a Simulator to a consumer.

 @param arguments the arguments for the log command.
 @param consumer the consumer to attach
 @return a Future that will complete when the log command has started successfully. The wrapped Awaitable can then be cancelled, or awaited until it is finished.
 */
- (FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBFileConsumer>)consumer;

/**
 Runs the log command, returning the results as an array of strings.

 @param arguments the arguments to the log command.
 @return a Future wrapping the log lines.
 */
- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
