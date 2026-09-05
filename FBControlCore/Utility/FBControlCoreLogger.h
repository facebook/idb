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
 A logger backed by os_log (falling back to NSLog).
 writeToStdErr additionally mirrors output to stderr unless os_log already does so in this environment.
 debugLogging selects the debug level rather than info.
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
 Trims surrounding whitespace and newlines; returns nil when nothing remains to log.
 */
+ (nullable NSString *)loggableStringLine:(nullable NSString *)string;

@end
