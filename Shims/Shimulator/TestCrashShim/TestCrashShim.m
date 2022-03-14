/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBDebugLog.h"

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

static NSString *ArchName(void)
{
#if TARGET_CPU_ARM64
  return @"arm64";
#elif TARGET_CPU_X86_64
  return @"x86_64";
#else
  return @"not supported");
#endif
}

static void PrintProcessInfo(void)
{
  FBDebugLog(@"Architecture %@",ArchName());

  NSProcessInfo *processInfo = NSProcessInfo.processInfo;
  NSLog(@"Arguments [%@]", [processInfo.arguments componentsJoinedByString:@" "]);

  FBDebugLog(@"Environment %@", processInfo.environment);
}

__attribute__((constructor)) static void EntryPoint()
{
  NSLog(@"Start of Shimulator");

  PrintProcessInfo();
  PerformCrashAfter();

  NSLog(@"End of Shimulator");
}
