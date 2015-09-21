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
 A protocol for defining a class that recieves logger messages.
 */
@protocol FBSimulatorLogger <NSObject>

- (void)logMessage:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end

@interface FBSimulatorLogger : NSObject

/**
 An implementation of `FBSimulatorLogger` that logs to NSLog
 */
+ (id<FBSimulatorLogger>)toNSLog;

@end
