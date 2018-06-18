/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
