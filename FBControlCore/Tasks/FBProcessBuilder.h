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
 stdin is not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @return a new Process Builder.
 */
+ (nonnull FBProcessBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(nonnull NSString *)launchPath;

/**
 Creates a new Process Builder with the provided launch path.
 stdin is not connected.
 stdout is written to NSData.
 stderr is written to NSData.

 @param launchPath the launch path to use. Must not be nil.
 @param arguments the arguments to launch with.
 @return a new Process Builder.
 */
+ (nonnull FBProcessBuilder<NSNull *, NSData *, NSData *> *)withLaunchPath:(nonnull NSString *)launchPath arguments:(nonnull NSArray<NSString *> *)arguments;

#pragma mark Spawn Configuration

/**
 The Launch Path of the Process

 @param launchPath the Launch Path.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)withLaunchPath:(nonnull NSString *)launchPath;

/**
 The Arguments of the Process.

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
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<id, StdOutType, StdErrType> *)withStdIn:(nonnull FBProcessInput *)input;

/**
 Creates a Data Consumer for stdin.

 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<id<FBDataConsumer>, StdOutType, StdErrType> *)withStdInConnected;

/**
 Creates a Data Consumer for stdin.

 @param data the data to send.
 @return the receiver, for chaining.
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
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, id<FBControlCoreLogger>, StdErrType> *)withStdOutToLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Redirects stdout to the provided logger and prints the output in any error message that occurs.

 @param logger the logger to use for logging lines.
 @return the receiver, for chaining.
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
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBControlCoreLogger>> *)withStdErrToLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Redirects stderr to the provided logger and prints the output in any error message that occurs.

 @param logger the logger to use for logging lines.
 @return the receiver, for chaining.
 */
- (nonnull FBProcessBuilder<StdInType, StdOutType, id<FBAccumulatingBuffer>> *)withStdErrToLoggerAndErrorMessage:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Logging

/**
 Logs the process lifecycle to the logger. Off by default; pass nil to disable.

 @param logger the logger to log to.
 @return the receiver for chaining.
 */
- (nonnull instancetype)withTaskLifecycleLoggingTo:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Building

/**
 Builds and starts the process.

 @return A future that resolves with the started process.
 */
- (nonnull FBFuture<FBSubprocess<StdInType, StdOutType, StdErrType> *> *)start;

/**
 Builds and starts the process, resolving once it has exited with one of the acceptable exit codes.
 Cancelling the process will cancel the task.

 @return a Future, encapsulating the process on completion.
 */
- (nonnull FBFuture<FBSubprocess<StdInType, StdOutType, StdErrType> *> *)runUntilCompletionWithAcceptableExitCodes:(nullable NSSet<NSNumber *> *)exitCodes;

@end
