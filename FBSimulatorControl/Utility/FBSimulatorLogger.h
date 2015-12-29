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
- (instancetype)log:(NSString *)string;

/**
 Logs a Message with the provided Format String.

 @param format the Format String for the Logger.
 @return the reciever, for chaining.
 */
- (instancetype)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

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
 Returns the Timestamped variant.
 */
- (id<FBSimulatorLogger>)timestamped;

@end

@interface FBSimulatorLogger : NSObject

/**
 An implementation of `FBSimulatorLogger` that logs events below an ASL Log Level.
 
 @param maxLevel the Maximum ASL Log Level to Log.
 @return an FBSimulatorLogger instance.
 */
+ (id<FBSimulatorLogger>)toNSLogWithMaxLevel:(int)maxLevel;

/**
 An implementation of `FBSimulatorLogger` that logs all events to NSLog.
 
 @return an FBSimulatorLogger instance.
 */
+ (id<FBSimulatorLogger>)toNSLog;

/**
 An implementation of `FBSimulatorLogger` that logs all events using ASL.

 @return an FBSimulatorLogger instance.
 */
+ (id<FBSimulatorLogger>)toASL;

@end
