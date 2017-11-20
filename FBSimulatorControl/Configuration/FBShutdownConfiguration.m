/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBShutdownConfiguration.h"

#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeListShutdown = @"shutdown";

@implementation FBShutdownConfiguration

#pragma mark FBiOSTargetFuture

- (FBiOSTargetFutureType)actionType
{
  return FBiOSTargetFutureTypeListShutdown;
}

- (FBFuture<FBiOSTargetFutureType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetFutureAwaitableDelegate>)awaitableDelegate
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not support FBSimulatorLifecycleCommands", target]
      failFuture];
  }
  return [[commands shutdown] mapReplace:self.actionType];
}

@end
