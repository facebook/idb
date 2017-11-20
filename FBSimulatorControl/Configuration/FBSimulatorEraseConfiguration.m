/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorEraseConfiguration.h"

#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeErase = @"erase";

@implementation FBSimulatorEraseConfiguration

- (FBiOSTargetFutureType)actionType
{
  return FBiOSTargetFutureTypeErase;
}

- (FBFuture<FBiOSTargetFutureType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetFutureAwaitableDelegate>)awaitableDelegate
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not conform to FBSimulatorLifecycleCommands", commands]
      failFuture];
  }
  return [[commands erase] mapReplace:self.actionType];
}

@end
