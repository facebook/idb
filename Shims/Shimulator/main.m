/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

static NSString *const ShimulatorCrashAfter = @"SHIMULATOR_CRASH_AFTER";

__attribute__((constructor)) static void EntryPoint()
{
  NSLog(@"Start of Shimulator");

  if (NSProcessInfo.processInfo.environment[ShimulatorCrashAfter]) {
    NSTimeInterval timeInterval = [NSProcessInfo.processInfo.environment[ShimulatorCrashAfter] doubleValue];
    NSLog(@"Forcing crash after %f seconds", timeInterval);
    [NSFileManager.defaultManager performSelector:@selector(stringWithFormat:) withObject:@"NOPE" afterDelay:timeInterval];
  }

  NSLog(@"End of Shimulator");
}
