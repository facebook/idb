/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>


static NSString *const ShimulatorCrashAfter = @"SHIMULATOR_CRASH_AFTER";

void FBPerformCrashAfter(void)
{
  if (!NSProcessInfo.processInfo.environment[ShimulatorCrashAfter]) {
    return;
  }
  NSTimeInterval timeInterval = [NSProcessInfo.processInfo.environment[ShimulatorCrashAfter] doubleValue];
  NSLog(@"Forcing crash after %f seconds", timeInterval);
  [NSFileManager.defaultManager performSelector:@selector(stringWithFormat:) withObject:@"NOPE" afterDelay:timeInterval];
}

void FBPrintProcessInfo(void)
{
  NSProcessInfo *processInfo = NSProcessInfo.processInfo;
  NSLog(@"Arguments [%@]", [processInfo.arguments componentsJoinedByString:@" "]);
}

