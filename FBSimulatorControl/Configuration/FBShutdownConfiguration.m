/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBShutdownConfiguration.h"

#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeListShutdown = @"shutdown";

@implementation FBShutdownConfiguration

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeListShutdown;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not support FBSimulatorLifecycleCommands", target]
      failFuture];
  }
  return [[commands shutdown] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
