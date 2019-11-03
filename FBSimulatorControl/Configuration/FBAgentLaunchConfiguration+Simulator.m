/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAgentLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBProcessLaunchConfiguration+Simulator.h"

@implementation FBAgentLaunchConfiguration (Simulator)

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeAgentLaunch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  if (![target isKindOfClass:FBSimulator.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ cannot launch an agent", target]
      failFuture];
  }
  FBSimulator *simulator = (FBSimulator *) target;
  return [[simulator launchAgent:self] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
