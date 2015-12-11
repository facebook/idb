/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSession+Convenience.h"

#import "FBProcessInfo+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Agents.h"
#import "FBSimulatorInteraction+Applications.h"
#import "FBSimulatorInteraction+Diagnostics.h"
#import "FBSimulatorSession+Private.h"

@implementation FBSimulatorSession_NotStarted (Convenience)

@end

@implementation FBSimulatorSession_Started (Convenience)

@end

@implementation FBSimulatorSession_Ended (Convenience)

- (BOOL)relaunchAppWithError:(NSError **)error
{
  return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Re-Launch App for an Ended Session" errorOut:error];
}

- (BOOL)terminateAppWithError:(NSError **)error
{
  return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Terminate App for an Ended Session" errorOut:error];
}

@end

@implementation FBSimulatorSession (Convenience)

- (BOOL)relaunchAppWithError:(NSError **)error
{
  FBApplicationLaunchConfiguration *launchConfig = self.history.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Re-Launch until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    launchApplication:launchConfig]
    performInteractionWithError:error];
}

- (BOOL)terminateAppWithError:(NSError **)error
{
  FBApplicationLaunchConfiguration *launchConfig = self.history.lastLaunchedApplication;
  if (!launchConfig) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot terminate until there is a last launched app" errorOut:error];
  }

  return [[[self interact]
    killApplication:launchConfig.application]
    performInteractionWithError:error];
}

@end
