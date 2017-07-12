/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBootConfiguration+Helpers.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"

@implementation FBSimulatorBootConfiguration (Helpers)

- (BOOL)shouldUseDirectLaunch
{
  return (self.options & FBSimulatorBootOptionsEnableDirectLaunch) == FBSimulatorBootOptionsEnableDirectLaunch;
}

- (BOOL)shouldConnectFramebuffer
{
  return self.framebuffer != nil;
}

- (BOOL)shouldLaunchViaWorkspace
{
  return (self.options & FBSimulatorBootOptionsUseNSWorkspace) == FBSimulatorBootOptionsUseNSWorkspace;
}

- (BOOL)shouldConnectBridge
{
  // If the option is flagged it should be used.
  if ((self.options & FBSimulatorBootOptionsConnectBridge) == FBSimulatorBootOptionsConnectBridge) {
    return YES;
  }
  // In some versions of Xcode 8, it was possible that a direct launch without a bridge could mean applications would not launch.
  if (!FBControlCoreGlobalConfiguration.isXcode9OrGreater && self.shouldUseDirectLaunch) {
    return YES;
  }
  return NO;
}

@end
