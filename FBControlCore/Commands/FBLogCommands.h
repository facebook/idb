/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetOperation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcess;

@protocol FBDataConsumer;

/**
 A logging operation of indeterminate duration.
 */
@protocol FBLogOperation <FBiOSTargetOperation>

/**
 The consumer of the operation.
 */
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

@end

/**
 A log operation that is contained within an FBProcess
 */
@interface FBProcessLogOperation : NSObject <FBLogOperation>

/**
 The wrapped launched process.
 */
@property (nonatomic, strong, readonly) FBProcess *process;

/**
 The Designated Initializer

 @param process the wrapped process.
 @param consumer the wrapped consumer.
 @param queue the queue to perform work on.
 @return an initialized FBProcessLogOperation instance.
 */
- (instancetype)initWithProcess:(FBProcess *)process consumer:(id<FBDataConsumer>)consumer queue:(dispatch_queue_t)queue;

/**
 Inserts the base "stream" argument into the argument array for os_log, if a subcommand is not already present.

 @param arguments the existing arguments
 @return a new arguments array containing either the original subcommand, or a stream subcommand.
 */
+ (NSArray<NSString *> *)osLogArgumentsInsertStreamIfNeeded:(NSArray<NSString *> *)arguments;

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

@end

NS_ASSUME_NONNULL_END
