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

@interface FBHostCrashLogCommands ()

@property (nonatomic, strong, readonly) FBCrashLogNotifier *notifier;

@end

@implementation FBHostCrashLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return [[self alloc] initWithNotifier:FBCrashLogNotifier.sharedInstance];
}

- (instancetype)initWithNotifier:(FBCrashLogNotifier *)notifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _notifier = notifier;

  return self;
}

#pragma mark id<FBiOSTarget>

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate
{
  return [self.notifier nextCrashLogForPredicate:predicate];
}

@end
