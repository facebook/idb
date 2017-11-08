/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBiOSTargetAction.h>

#import <objc/runtime.h>

#import "NSRunLoop+FBControlCore.h"


FBiOSTargetActionType const FBiOSTargetActionTypeApplicationLaunch = @"applaunch";

FBiOSTargetActionType const FBiOSTargetActionTypeAgentLaunch = @"agentlaunch";

FBiOSTargetActionType const FBiOSTargetActionTypeTestLaunch = @"launch_xctest";

static BOOL BridgedRun(id<FBiOSTargetFuture> targetFuture, SEL _cmd, id<FBiOSTarget> target, id<FBiOSTargetActionDelegate> delegate, NSError **error)
{
  id<FBFileConsumer> consumer = [delegate obtainConsumerForAction:(id<FBiOSTargetAction>)targetFuture target:target];
  FBFuture *future = [targetFuture runWithTarget:target consumer:consumer reporter:delegate awaitableDelegate:delegate];
  id result = [future await:error];
  return result != nil;
}

id<FBiOSTargetAction> FBiOSTargetActionFromTargetFuture(id<FBiOSTargetFuture> targetFuture)
{
  // Return early if we already conform
  Class class = targetFuture.class;
  Protocol *protocol = @protocol(FBiOSTargetAction);
  SEL selector = @selector(runWithTarget:delegate:error:);
  if (class_conformsToProtocol(class, protocol)) {
    return (id<FBiOSTargetAction>) targetFuture;
  };
  // Add the Method and Protocol conformance
  const char *encoding = protocol_getMethodDescription(protocol, selector, YES, YES).types;
  NSCParameterAssert(class_addMethod(class, selector, (IMP) BridgedRun, encoding));
  NSCParameterAssert(class_addProtocol(class, protocol));
  return (id<FBiOSTargetAction>) targetFuture;
}

@implementation FBiOSTargetActionSimple

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

- (BOOL)isEqual:(FBiOSTargetActionSimple *)configuration
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
