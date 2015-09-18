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
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorSessionInteraction+Diagnostics.h"
#import "FBSimulatorSessionInteraction.h"
#import "FBSimulatorSessionState+Queries.h"

@implementation FBSimulatorSession (Convenience)

- (BOOL)startWithAppLaunch:(FBApplicationLaunchConfiguration *)appLaunch agentLaunch:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Cannot Launch App & Agent for an Ended Session" errorOut:error];
  }
  return [[[self interact]
    startWithAppLaunch:appLaunch agentLaunch:agentLaunch]
    performInteractionWithError:error];
}

- (BOOL)relaunchAppWithError:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Cannot Re-Launch App for an Ended Session" errorOut:error];
  }

  FBApplicationLaunchConfiguration *launchConfig = self.state.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Cannot Re-Launch until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    launchApplication:launchConfig]
    performInteractionWithError:error];
}

- (BOOL)terminateAppWithError:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Cannot Terminate App for an Ended Session" errorOut:error];
  }

  FBApplicationLaunchConfiguration *launchConfig = self.state.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Cannot terminate until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    killApplication:launchConfig.application]
    performInteractionWithError:error];
}

@end

@implementation FBSimulatorSessionInteraction (Convenience)

- (instancetype)startWithAppLaunch:(FBApplicationLaunchConfiguration *)appLaunch agentLaunch:(FBAgentLaunchConfiguration *)agentLaunch
{
  return [[[[[[self
    bootSimulator]
    installApplication:appLaunch.application]
    launchAgent:agentLaunch]
    launchApplication:appLaunch] retry:3]
    sampleApplication:appLaunch.application withDuration:20 frequency:5];
}

@end
