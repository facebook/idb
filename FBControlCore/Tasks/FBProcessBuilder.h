/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBSubprocess.h>

@protocol FBAccumulatingBuffer;
@protocol FBControlCoreLogger;
@protocol FBDataConsumer;

@class FBFuture;
@class FBProcessInput;

/**
 An interface to building FBProcess instances.
 */
@interface FBProcessBuilder <StdInType : id, StdOutType : id, StdErrType : id> : NSObject

#pragma mark Initializers

/**
 Creates a new Process Builder with the provided launch path.
 stdin is not not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @return a new Process Builder.
 */
+ (nonnull FBProcessBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(nonnull NSString *)launchPath;

/**
 Creates a new Process Builder with the provided launch path.
 stdin is not not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @param arguments the arguments to launch with.
 @return a new Process Builder.
 */
+ (nonnull FBProcessBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(nonnull NSString *)launchPath arguments:(nonnull NSArray<NSString *> *)arguments;

#pragma mark Spawn Configuration

/**
 The Launch Path of the Proces

 @param launchPath the Launch Path. Will remove shellCommand.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)withLaunchPath:(nonnull NSString *)launchPath;

/**
 The Arguments of the Process..

 @param arguments the arguments for the launch path.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)withArguments:(nonnull NSArray<NSString *> *)arguments;

/**
 Replaces the environment with the provided environment dictionary.

 @param environment an Environment Dictionary. Must not be nil.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)withEnvironment:(nonnull NSDictionary<NSString *, NSString *> *)environment;

/**
 Adds the provided dictionary to the environment of the built process.

 @param environment an Environment Dictionary. Must not be nil.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)withEnvironmentAdditions:(nonnull NSDictionary<NSString *, NSString *> *)environment;

#pragma mark stdin

/**
 Passes an process input to stdin.

 @param input the input to pass
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<id, StdOutType, StdErrType> *)withStdIn:(nonnull FBProcessInput *)input;

/**
 Creates a Data Consumer for stdin.

 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<id<FBDataConsumer>, StdOutType, StdErrType> *)withStdInConnected;

/**
 Creates a Data Consumer for stdin.

 @param data the data to send.
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<NSData *, StdOutType, StdErrType> *)withStdInFromData:(nonnull NSData *)data;

#pragma mark stdout

/**
 Reads stdout into memory, as a Data.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, NSData *, StdErrType> *)withStdOutInMemoryAsData;

/**
 Reads stdout into memory, as a String.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, NSString *, StdErrType> *)withStdOutInMemoryAsString;

/**
 Assigns a path to write stdout to.

 @param stdOutPath the path to write stdout to. Must not be nil.
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, NSString *, StdErrType> *)withStdOutPath:(nonnull NSString *)stdOutPath;

/**
 Redirects stdout to /dev/null

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, NSNull *, StdErrType> *)withStdOutToDevNull;

/**
 Redirects stdout to an input stream.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, NSInputStream *, StdErrType> *)withStdOutToInputStream;

/**
 Redirects stdout data to the consumer.

 @param consumer the consumer to consume the data.
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, id<FBDataConsumer>, StdErrType> *)withStdOutConsumer:(nonnull id<FBDataConsumer>)consumer;

/**
 Redirects stdout to the reader block, on a per line basis.

 @param reader the block to use for reading lines
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, id<FBDataConsumer>, StdErrType> *)withStdOutLineReader:(nonnull void (^)(NSString * _Nonnull))reader;

/**
 Redirects stdout to the provided logger, on a per line basis.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, id<FBControlCoreLogger>, StdErrType> *)withStdOutToLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Redirects stdout to the provided logger and prints the output in any error message that occurs.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, id<FBAccumulatingBuffer>, StdErrType> *)withStdOutToLoggerAndErrorMessage:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark stderr

/**
 Reads stderr into memory, as a Data.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdInType, NSData *> *)withStdErrInMemoryAsData;

/**
 Reads stderr into memory, as a String.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, NSString *> *)withStdErrInMemoryAsString;

/**
 Assigns a path to write stderr to.

 @param stdErrPath the path to write stderr to. Must not be nil.
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, NSString *> *)withStdErrPath:(nonnull NSString *)stdErrPath;

/**
 Redirects stderr to /dev/null

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, NSNull *> *)withStdErrToDevNull;

/**
 Redirects stderr data to the consumer.

 @param consumer the consumer to consume the data.
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBDataConsumer>> *)withStdErrConsumer:(nonnull id<FBDataConsumer>)consumer;

/**
 Redirects stderr to the reader block, on a per line basis.

 @param reader the block to use for reading lines
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBDataConsumer>> *)withStdErrLineReader:(nonnull void (^)(NSString * _Nonnull))reader;

/**
 Redirects stderr to the provided logger, on a per line basis.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBControlCoreLogger>> *)withStdErrToLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Redirects stderr to the provided logger and prints the output in any error message that occurs.

 @param logger the logger to use for logging lines.
 @return the reciver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBAccumulatingBuffer>> *)withStdErrToLoggerAndErrorMessage:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Logging

/**
 Enables logging of the process lifecycle to the provided logger.
 By default the task will be constructed without this logging.
 To get detailed information, pass a logger to this method.
 Logging can be disabled by passing nil.

 @param logger the logger to log to. Nil may be passed to disable task lifecycle logging, which is the default.
 @return the receiver for chaining.
 */
- (nonnull instancetype)withTaskLifecycleLoggingTo:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Building

/**
 Builds and starts the process.

 @return A future that resolves with the started process..
 */
- (nonnull FBFuture<FBSubprocess<StdInType, StdOutType, StdErrType> *> *)start;

/**
 Builds and starts the process, then waits for it to complete with the provided exit codes.
 The future will resolve when the process has finished executing.
 Cancelling the process will cancel the task.

 @return a Future, encapsulating the process on completion.
 */
- (nonnull FBFuture<FBSubprocess<StdInType, StdOutType, StdErrType> *> *)runUntilCompletionWithAcceptableExitCodes:(nullable NSSet<NSNumber *> *)exitCodes;

@end
