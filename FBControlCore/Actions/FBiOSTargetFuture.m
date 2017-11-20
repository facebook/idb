/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBiOSTargetFuture.h>

#import <objc/runtime.h>

#import "NSRunLoop+FBControlCore.h"


FBiOSTargetFutureType const FBiOSTargetFutureTypeApplicationLaunch = @"applaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeAgentLaunch = @"agentlaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeTestLaunch = @"launch_xctest";

@implementation FBiOSTargetFutureSimple

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

- (nonnull id)jsonSerializableRepresentation
{
  return @{};
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  return [self new];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBiOSTargetFutureSimple *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }
  return YES;
}

- (NSUInteger)hash
{
  return NSStringFromClass(self.class).hash;
}

@end
