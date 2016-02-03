/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 A Protocol for Classes that recieve Logger Messages.
 */
@protocol FBSimulatorLogger <NSObject>

/**
 Logs a Message with the provided String.

 @param string the string to log.
 @return the reciever, for chaining.
 */
- (id<FBSimulatorLogger>)log:(NSString *)string;

/**
 Logs a Message with the provided Format String.

 @param format the Format String for the Logger.
 @return the reciever, for chaining.
 */
- (id<FBSimulatorLogger>)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Returns the Info Logger variant.
 */
- (id<FBSimulatorLogger>)info;

/**
 Returns the Debug Logger variant.
 */
- (id<FBSimulatorLogger>)debug;

/**
 Returns the Error Logger variant.
 */
- (id<FBSimulatorLogger>)error;

/**
 Returns a Logger that will accept log values on the given queue.

 @param queue the queue to accept log messages on.
 @return a new Logger that will allows logging of messages on the provided queue.
 */
- (id<FBSimulatorLogger>)onQueue:(dispatch_queue_t)queue;

@end

@interface FBSimulatorLogger : NSObject

/**
 An implementation of `FBSimulatorLogger` that logs all events using ASL.

 @param writeToStdErr YES if all future log messages should be written to stderr, NO otherwise.
 @param debugLogging YES if Debug messages should be written to stderr, NO otherwise.
 @return an FBSimulatorLogger instance.
 */
+ (id<FBSimulatorLogger>)aslLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging;

@end
