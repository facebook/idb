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

FBiOSTargetActionType const FBiOSTargetActionTypeErase = @"erase";

@implementation FBSimulatorEraseConfiguration

- (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeErase;
}

- (FBFuture<FBiOSTargetActionType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetActionAwaitableDelegate>)awaitableDelegate
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
