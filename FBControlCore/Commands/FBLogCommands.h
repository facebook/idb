/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;

/**
 A logging operation of indeterminate duration.
 */
@protocol FBLogOperation <FBiOSTargetContinuation>

/**
 The consumer of the operation.
 */
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

@end

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
- (FBFuture<id<FBLogOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer;

/**
 Runs the log command, returning the results as an array of strings.

 @param arguments the arguments to the log command.
 @return a Future wrapping the log lines.
 */
- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
