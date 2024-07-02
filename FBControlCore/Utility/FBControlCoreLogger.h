/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

/**
 A Protocol for Classes that receive Logger Messages.
 */
@protocol FBControlCoreLogger <NSObject>

#pragma mark Public Methods

/**
 Logs a Message with the provided String.

 @param message the message to log.
 @return the receiver, for chaining.
 */
- (id<FBControlCoreLogger>)log:(NSString *)message;

/**
 Logs a Message with the provided Format String.

 @param format the Format String for the Logger.
 @return the receiver, for chaining.
 */
- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Returns the Info Logger variant.
 */
- (id<FBControlCoreLogger>)info;

/**
 Returns the Debug Logger variant.
 */
- (id<FBControlCoreLogger>)debug;

/**
 Returns the Error Logger variant.
 */
- (id<FBControlCoreLogger>)error;

/**
 Returns a Logger for a named 'facility' or 'tag'.

 @param name the name to apply to all messages.
 @return a new Logger that will allows logging of messages on the provided queue.
 */
- (id<FBControlCoreLogger>)withName:(NSString *)name;

/**
 Enables or Disables date formatting in the logger.

 @param enabled YES to enable date formatting, NO otherwise.
 @return a new Logger with the date formatting applied.
 */
- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled;

#pragma mark Properties

/**
 The Prefix for the Logger, if set.
 */
@property (nonatomic, copy, nullable, readonly) NSString *name;

/**
 The Current Log Level
 */
@property (nonatomic, assign, readonly) FBControlCoreLogLevel level;

@end

/**
  A composite logger that logs to many loggers
 */
@interface FBCompositeLogger : NSObject <FBControlCoreLogger>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param loggers the loggers to log to.
 @return a composite logger.
 */
- (instancetype)initWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers;

#pragma mark Properties

/**
  The loggers to log to.
 */
@property (nonatomic, strong, readonly) NSArray<id<FBControlCoreLogger>> *loggers;

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
+ (id<FBControlCoreLogger>)systemLoggerWritingToStderr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging;

/**
 Compose multiple loggers into one.
 
 @param loggers the loggers to compose.
 @return the composite logger.
 */
+ (FBCompositeLogger *)compositeLoggerWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers;

/**
 Log to a Consumer.

 @param consumer the consumer to write data to.
 @return a logger instance.
 */
+ (id<FBControlCoreLogger>)loggerToConsumer:(id<FBDataConsumer>)consumer;

/**
 Log to a File Descriptor.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @return a logger instance.
 */
+ (id<FBControlCoreLogger>)loggerToFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile;

/**
 Strips the newline and returns a nullable string if the string shouldn't be logged.

 @param string the string to log.
 @return the modifier string.
 */
+ (nullable NSString *)loggableStringLine:(nullable NSString *)string;

@end

NS_ASSUME_NONNULL_END
