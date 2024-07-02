/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>
#import "FBSimulatorNotificationCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import <FBControlCore/FBiOSTarget.h>

@interface FBSimulatorNotificationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorNotificationCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBNotificationCommands Protocol Implementation

- (FBFuture<NSNull *> *)sendPushNotificationForBundleID:(NSString *)bundleID jsonPayload:(NSString *)jsonPayload;
{
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *jsonObj = [NSJSONSerialization
                                           JSONObjectWithData:[jsonPayload dataUsingEncoding:NSUTF8StringEncoding]
                                           options:0
                                           error:&jsonError];
  if (jsonError) {
    return [[FBSimulatorError describeFormat:@"Failed to deserialize notification json: %@", jsonError] failFuture];
  }

  if ([self.simulator.device respondsToSelector:(@selector(sendPushNotificationForBundleID:jsonPayload:error:))]) {
    return [FBFuture onQueue:self.simulator.workQueue resolve:^ FBFuture<NSNull *> * () {
      NSError *error = nil;
      [self.simulator.device sendPushNotificationForBundleID:bundleID jsonPayload:jsonObj error:&error];
      if (error) {
        return [FBFuture futureWithError:error];
      }

      return FBFuture.empty;
    }];
  }

  return [[FBSimulatorError
            describe:@"SimDevice doesn't have sendPushNotificationForBundleID selector"]
            failFuture];
}

@end
