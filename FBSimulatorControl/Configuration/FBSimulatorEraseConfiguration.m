/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorEraseConfiguration.h"

#import "FBSimulatorLifecycleCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeErase = @"erase";

@implementation FBSimulatorEraseConfiguration

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeErase;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not conform to FBSimulatorLifecycleCommands", commands]
      failFuture];
  }
  return [[commands erase] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
