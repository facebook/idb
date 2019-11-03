/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAccessibilityFetch.h"

#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeAccessibilityFetch = @"accessibility_fetch";

@implementation FBAccessibilityFetch

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeAccessibilityFetch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
     describeFormat:@"%@ does not conform to FBSimulatorLifecycleCommands", target]
     failFuture];
  }

  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  return [[[commands
    connectToBridge]
    onQueue:target.workQueue fmap:^(FBSimulatorBridge *bridge) {
      return [bridge accessibilityElements];
    }]
    onQueue:target.asyncQueue fmap:^ FBFuture<id<FBiOSTargetContinuation>> * (NSArray<NSDictionary<NSString *, id> *> *elements) {
      NSError *error = nil;
      NSData *data = [NSJSONSerialization dataWithJSONObject:elements options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      [consumer consumeData:data];
      return [FBFuture futureWithResult:FBiOSTargetContinuationDone(self.class.futureType)];
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
  return FBiOSTargetFutureTypeAccessibilityFetch;
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
