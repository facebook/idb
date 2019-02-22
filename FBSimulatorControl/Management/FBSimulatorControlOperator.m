/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlOperator.h"

#import "FBSimulatorError.h"
#import "FBSimulator.h"

@interface FBSimulatorControlOperator ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorControlOperator

+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator
{
  return [[FBSimulatorControlOperator alloc] initWithSimulator:simulator];
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

#pragma mark - FBApplicationCommands

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  return [[self.simulator
    serviceNameAndProcessIdentifierForSubstring:bundleID]
    onQueue:self.simulator.asyncQueue fmap:^(NSArray<id> *result) {
      NSNumber *processIdentifier = result[1];
      if (processIdentifier.intValue < 1) {
        return [[FBSimulatorError
          describeFormat:@"Service %@ does not have a running process", result[0]]
          failFuture];
      }
      return [FBFuture futureWithResult:processIdentifier];
    }];
}

@end
