/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCrashLogCommands.h"

#import "FBCrashLogNotifier.h"

@implementation FBHostCrashLogCommands

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return [self new];
}

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(pid_t)processIdentifier
{
  return [FBCrashLogNotifier nextCrashLogForProcessIdentifier:processIdentifier];
}

@end
