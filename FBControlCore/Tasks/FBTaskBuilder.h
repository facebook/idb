/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBTask.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@protocol FBFileConsumer;

@class FBFuture;

/**
 An interface to building FBTask instances.
 */
@interface FBTaskBuilder <StdInType : id, StdOutType : id, StdErrType : id> : NSObject

#pragma mark Initializers

/**
 Creates a new Task Builder with the provided launch path.
 stdin is not not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @return a new Task Builder.
 */
+ (FBTaskBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(NSString *)launchPath;

/**
 Creates a new Task Builder with the provided launch path.
 stdin is not not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @param arguments the arguments to launch with.
 @return a new Task Builder.
 */
+ (FBTaskBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments;

#pragma mark Spawn Configuration

/**
 The Launch Path of the Task. Will override any shell command set with `shellCommand`.

 @param launchPath the Launch Path. Will remove shellCommand.
 @return the reciever, for chaining.
 */
- (instancetype)withLaunchPath:(NSString *)launchPath;

/**
 The Arguments of the Task. Will override any shell command set with `shellCommand`.

 @param arguments the arguments for the launch path.
 @return the reciever, for chaining.
 */
- (instancetype)withArguments:(NSArray<NSString *> *)arguments;

/**
 Replaces the Subprocess Environment with the provided Environment.

 @param environment an Environment Dictionary. Must not be nil.
 @return the reciever, for chaining.
 */
- (instancetype)withEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/**
 Adds the provided dictionary to the environment of the built task.

 @param environment an Environment Dictionary. Must not be nil.
 @return the reciever, for chaining.
 */
- (instancetype)withEnvironmentAdditions:(NSDictionary<NSString *, NSString *> *)environment;

/**
 The Set of Return Codes that are considered non-erroneous.

 @param statusCodes the non-erroneous stats codes.
 @return the reciever, for chaining.
 */
- (instancetype)withAcceptableTerminationStatusCodes:(NSSet<NSNumber *> *)statusCodes;

#pragma mark Input/Output

/**
 Reads stdout into memory, as a Data.

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, NSData *, StdErrType> *)withStdOutInMemoryAsData;

/**
 Reads stderr into memory, as a Data.

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdInType, NSData *> *)withStdErrInMemoryAsData;

/**
 Reads stdout into memory, as a String.

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, NSString *, StdErrType> *)withStdOutInMemoryAsString;

/**
 Reads stderr into memory, as a String.

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, NSString *> *)withStdErrInMemoryAsString;

/**
 Assigns a path to write stdout to.

 @param stdOutPath the path to write stdout to. Must not be nil.
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, NSString *, StdErrType> *)withStdOutPath:(NSString *)stdOutPath;

/**
 Assigns a path to write stderr to.

 @param stdErrPath the path to write stderr to. Must not be nil.
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, NSString *> *)withStdErrPath:(NSString *)stdErrPath;

/**
 Redirects stdout to /dev/null

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, NSNull *, StdErrType> *)withStdOutToDevNull;

/**
 Redirects stderr to /dev/null

 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, NSNull *> *)withStdErrToDevNull;

/**
 Redirects stdout data to the consumer.

 @param consumer the consumer to consume the data.
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, id<FBFileConsumer>, StdErrType> *)withStdOutConsumer:(id<FBFileConsumer>)consumer;

/**
 Redirects stderr data to the consumer.

 @param consumer the consumer to consume the data.
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, id<FBFileConsumer>> *)withStdErrConsumer:(id<FBFileConsumer>)consumer;

/**
 Redirects stdout to the reader block, on a per line basis.

 @param reader the block to use for reading lines
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, id<FBFileConsumer>, StdErrType> *)withStdOutLineReader:(void (^)(NSString *))reader;

/**
 Redirects stderr to the reader block, on a per line basis.

 @param reader the block to use for reading lines
 @return the reciever, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, id<FBFileConsumer>> *)withStdErrLineReader:(void (^)(NSString *))reader;

/**
 Redirects stdout to the provided logger, on a per line basis.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (FBTaskBuilder<StdInType, id<FBControlCoreLogger>, StdErrType> *)withStdOutToLogger:(id<FBControlCoreLogger>)logger;

/**
 Redirects stderr to the provided logger, on a per line basis.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (FBTaskBuilder<StdInType, StdOutType, id<FBControlCoreLogger>> *)withStdErrToLogger:(id<FBControlCoreLogger>)logger;

/**
 Creates a File Consumer for stdin.

 @return the reciver, for chaining.
 */
- (FBTaskBuilder<id<FBFileConsumer>, StdOutType, StdErrType> *)withStdInConnected;

/**
 Creates a File Consumer for stdin.

 @param data the data to send.
 @return the reciver, for chaining.
 */
- (FBTaskBuilder<NSData *, StdOutType, StdErrType> *)withStdInFromData:(NSData *)data;

#pragma mark Building

/**
 Builds and Starts the Task.

 @return a FBTask.
 */
- (FBFuture<FBTask<StdInType, StdOutType, StdErrType> *> *)start;

/**
 Builds and Starts Task, wrapping it in a future.
 The future will resolve when the task has finished executing.
 Cancelling the future will cancel the task.

 @return a Future, encapsulating the task on completion.
 */
- (FBFuture<FBTask<StdInType, StdOutType, StdErrType> *> *)runUntilCompletion;

@end

NS_ASSUME_NONNULL_END
