/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

@protocol FBFileConsumer;

/**
 A Protocol for Classes that recieve Logger Messages.
 */
@protocol FBControlCoreLogger <NSObject>

#pragma mark Public Methods

/**
 Logs a Message with the provided String.

 @param message the message to log.
 @return the reciever, for chaining.
 */
- (id<FBControlCoreLogger>)log:(NSString *)message;

/**
 Logs a Message with the provided Format String.

 @param format the Format String for the Logger.
 @return the reciever, for chaining.
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
 Implementations of Loggers.
 */
@interface FBControlCoreLogger : NSObject

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
+ (id<FBControlCoreLogger>)compositeLoggerWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers;

/**
 Log to a Consumer.

 @param consumer the consumer to write data to.
 @return a logger instance.
 */
+ (id<FBControlCoreLogger>)loggerToConsumer:(id<FBFileConsumer>)consumer;

/**
 Log to a File Handle.

 @param fileHandle the file handle to write to.
 @return a logger instance.
 */
+ (id<FBControlCoreLogger>)loggerToFileHandle:(NSFileHandle *)fileHandle;

@end

NS_ASSUME_NONNULL_END
