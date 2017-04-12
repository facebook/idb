/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAgentLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

FBiOSTargetActionType const FBiOSTargetActionTypeAgentLaunch = @"agentlaunch";

@implementation FBAgentLaunchConfiguration (Simulator)

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeAgentLaunch;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error;
{
  if (![target isKindOfClass:FBSimulator.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ cannot launch an agent", target]
      failBool:error];
  }
  FBSimulator *simulator = (FBSimulator *) target;
  return [simulator launchAgent:self error:error];
}

@end
