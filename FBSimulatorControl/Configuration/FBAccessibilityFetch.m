/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAccessibilityFetch.h"

#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetActionType const FBiOSTargetActionTypeAcessibilityFetch = @"accessibility_fetch";

@implementation FBAccessibilityFetch

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeAcessibilityFetch;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
     describeFormat:@"%@ does not conform to FBSimulatorLifecycleCommands", target]
     failBool:error];
  }

  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  FBSimulatorBridge *bridge = [[commands connectWithError:error] connectToBridge:error];
  if (!bridge) {
    return NO;
  }
  id<FBFileConsumer> consumer = [delegate obtainConsumerForAction:self target:target];
  NSArray *elements = [bridge accessibilityElements];
  NSData *data = [NSJSONSerialization dataWithJSONObject:elements options:0 error:error];
  [consumer consumeData:data];
  return YES;
}

- (id)jsonSerializableRepresentation
{
  return @{};
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"Expected an input of Dictionary<String, Object> got %@", json]
      fail:error];
  }
  return [self new];
}

#pragma mark NSObject

- (NSString *)description
{
  return FBiOSTargetActionTypeAcessibilityFetch;
}

- (BOOL)isEqual:(FBAccessibilityFetch *)object
{
  return [object isKindOfClass:self.class];
}

- (NSUInteger)hash
{
  return 42;
}

@end
