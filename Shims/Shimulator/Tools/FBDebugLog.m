/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDebugLog.h"

static NSString *const ShimulatorDebugMode = @"SHIMULATOR_DEBUG";

void FBDebugLog(NSString *format, ...)
{
  if (!NSProcessInfo.processInfo.environment[ShimulatorDebugMode]) {
    return;
  }
  va_list args;
  va_start(args, format);
  NSLogv(format, args);
  va_end(args);
}
