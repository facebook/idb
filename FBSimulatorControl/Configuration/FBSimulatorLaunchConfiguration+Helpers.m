/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchConfiguration+Helpers.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"

@implementation FBSimulatorLaunchConfiguration (Helpers)

 - (NSArray *)xcodeSimulatorApplicationArgumentsForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  // Construct the Arguments
  NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[
    @"--args",
    @"-CurrentDeviceUDID", simulator.udid,
    @"-ConnectHardwareKeyboard", @"0",
    [self lastScaleCommandLineSwitchForSimulator:simulator], self.scaleString
  ]];
  if (simulator.pool.configuration.deviceSetPath) {
    if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
      return [[[FBSimulatorError describe:@"Cannot use custom Device Set on current platform"] inSimulator:simulator] fail:error];
    }
    [arguments addObjectsFromArray:@[@"-DeviceSetPath", simulator.pool.configuration.deviceSetPath]];
  }
  return [arguments copy];
}

#pragma mark Scale

- (NSString *)lastScaleCommandLineSwitchForSimulator:(FBSimulator *)simulator
{
  return [NSString stringWithFormat:@"-SimulatorWindowLastScale-%@", simulator.device.deviceTypeIdentifier];
}

@end
