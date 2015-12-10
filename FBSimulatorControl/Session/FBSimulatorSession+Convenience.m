/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSession+Convenience.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Agents.h"
#import "FBSimulatorInteraction+Applications.h"
#import "FBSimulatorInteraction+Diagnostics.h"
#import "FBSimulatorSessionState+Queries.h"

@implementation FBSimulatorSession (Convenience)

- (BOOL)relaunchAppWithError:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Re-Launch App for an Ended Session" errorOut:error];
  }

  FBApplicationLaunchConfiguration *launchConfig = self.state.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Re-Launch until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    launchApplication:launchConfig]
    performInteractionWithError:error];
}

- (BOOL)terminateAppWithError:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Terminate App for an Ended Session" errorOut:error];
  }

  FBApplicationLaunchConfiguration *launchConfig = self.state.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot terminate until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    killApplication:launchConfig.application]
    performInteractionWithError:error];
}

@end
