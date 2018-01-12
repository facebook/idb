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

FBiOSTargetFutureType const FBiOSTargetFutureTypeAcessibilityFetch = @"accessibility_fetch";

@implementation FBAccessibilityFetch

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeAcessibilityFetch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
     describeFormat:@"%@ does not conform to FBSimulatorLifecycleCommands", target]
     failFuture];
  }

  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  return [[commands
    connectToBridge]
    onQueue:target.workQueue fmap:^ FBFuture<id<FBiOSTargetContinuation>> * (FBSimulatorBridge *bridge) {
      NSArray<NSDictionary<NSString *, id> *> *elements = [bridge accessibilityElements];
      NSError *error = nil;
      NSData *data = [NSJSONSerialization dataWithJSONObject:elements options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      [consumer consumeData:data];
      return FBiOSTargetContinuationDone(self.class.futureType);
    }];
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
  return FBiOSTargetFutureTypeAcessibilityFetch;
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
