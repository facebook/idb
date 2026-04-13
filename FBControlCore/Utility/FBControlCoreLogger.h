/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 The Log Level.
 The Multiple Level exists so that composite loggers can decide whether to log individually.
 */
typedef NS_ENUM(NSUInteger, FBControlCoreLogLevel) {
  FBControlCoreLogLevelError = 1,
  FBControlCoreLogLevelInfo = 2,
  FBControlCoreLogLevelDebug = 3,
  FBControlCoreLogLevelMultiple = 1000,
};

@protocol FBDataConsumer;

// Protocol defined in Swift (FBControlCoreLoggerProtocol.swift)
@protocol FBControlCoreLogger;

/**
  A composite logger that logs to many loggers
 */
@interface FBCompositeLogger : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param loggers the loggers to log to.
 @return a composite logger.
 */
- (nonnull instancetype)initWithLoggers:(nonnull NSArray<id<FBControlCoreLogger>> *)loggers;

#pragma mark Properties

/**
  The loggers to log to.
 */
@property (nonnull, nonatomic, readonly, strong) NSArray<id<FBControlCoreLogger>> *loggers;

- (nonnull id<FBControlCoreLogger>)log:(nonnull NSString *)message;
- (nonnull id<FBControlCoreLogger>)info;
- (nonnull id<FBControlCoreLogger>)debug;
- (nonnull id<FBControlCoreLogger>)error;
- (nonnull id<FBControlCoreLogger>)withName:(nonnull NSString *)name;
- (nonnull id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled;
@property (nullable, nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, assign) FBControlCoreLogLevel level;

@end

/**
 Implementations of Loggers.
 */
@interface FBControlCoreLoggerFactory : NSObject

/**
 An implementation of `FBControlCoreLogger` that logs using the OS's default logging framework.
 Optionally logs to stderr.

 @param writeToStdErr YES if all future log messages should be written to stderr, NO otherwise.
 @param debugLogging YES if Debug messages should be written to stderr, NO otherwise.
 @return an FBControlCoreLogger instance.
 */
+ (nonnull id<FBControlCoreLogger>)systemLoggerWritingToStderr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging;

/**
 Compose multiple loggers into one.

 @param loggers the loggers to compose.
 @return the composite logger.
 */
+ (nonnull FBCompositeLogger *)compositeLoggerWithLoggers:(nonnull NSArray<id<FBControlCoreLogger>> *)loggers;

/**
 Log to a Consumer.

 @param consumer the consumer to write data to.
 @return a logger instance.
 */
+ (nonnull id<FBControlCoreLogger>)loggerToConsumer:(nonnull id<FBDataConsumer>)consumer;

/**
 Log to a File Descriptor.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @return a logger instance.
 */
+ (nonnull id<FBControlCoreLogger>)loggerToFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile;

/**
 Strips the newline and returns a nullable string if the string shouldn't be logged.

 @param string the string to log.
 @return the modifier string.
 */
+ (nullable NSString *)loggableStringLine:(nullable NSString *)string;

@end
