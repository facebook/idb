/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogger.h"

@interface FBSimulatorLogger_NSLog : NSObject<FBSimulatorLogger>

@end

@implementation FBSimulatorLogger_NSLog

- (void)logMessage:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSLogv(format, args);
  va_end(args);
}

@end

@implementation FBSimulatorLogger

+ (id<FBSimulatorLogger>)toNSLog
{
  return [FBSimulatorLogger_NSLog new];
}

@end
