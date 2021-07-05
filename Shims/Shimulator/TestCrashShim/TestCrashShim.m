/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>


static NSString *const ShimulatorCrashAfter = @"SHIMULATOR_CRASH_AFTER";

static void PerformCrashAfter(void)
{
  if (!NSProcessInfo.processInfo.environment[ShimulatorCrashAfter]) {
    return;
  }
  NSTimeInterval timeInterval = [NSProcessInfo.processInfo.environment[ShimulatorCrashAfter] doubleValue];
  NSLog(@"Forcing crash after %f seconds", timeInterval);
  [NSFileManager.defaultManager performSelector:@selector(stringWithFormat:) withObject:@"NOPE" afterDelay:timeInterval];
}

static void PrintProcessInfo(void)
{
  NSProcessInfo *processInfo = NSProcessInfo.processInfo;
  NSLog(@"Arguments [%@]", [processInfo.arguments componentsJoinedByString:@" "]);
}

__attribute__((constructor)) static void EntryPoint()
{
  NSLog(@"Start of Shimulator");

  PrintProcessInfo();
  PerformCrashAfter();

  NSLog(@"End of Shimulator");
}
