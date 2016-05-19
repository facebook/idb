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
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"

@implementation FBSimulatorLaunchConfiguration (Helpers)

 - (NSArray *)xcodeSimulatorApplicationArgumentsForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  // These arguments are based on the NSUserDefaults that are serialized for the Simulator.app.
  // These can be seen with `defaults read com.apple.iphonesimulator` and has default location of ~/Library/Preferences/com.apple.iphonesimulator.plist
  // NSUserDefaults for any application can be overriden in the NSArgumentDomain:
  // https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html#//apple_ref/doc/uid/10000059i-CH2-96930
  NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[
    @"--args",
    @"-CurrentDeviceUDID", simulator.udid,
    @"-ConnectHardwareKeyboard", @"0",
    [self lastScaleCommandLineSwitchForSimulator:simulator], self.scaleString
  ]];
  NSString *setPath = simulator.set.deviceSet.setPath;
  if (setPath) {
    if (!FBControlCoreGlobalConfiguration.supportsCustomDeviceSets) {
      return [[[FBSimulatorError describe:@"Cannot use custom Device Set on current platform"] inSimulator:simulator] fail:error];
    }
    [arguments addObjectsFromArray:@[@"-DeviceSetPath", setPath]];
  }
  return [arguments copy];
}

- (BOOL)shouldUseDirectLaunch
{
  return (self.options & FBSimulatorLaunchOptionsEnableDirectLaunch) == FBSimulatorLaunchOptionsEnableDirectLaunch;
}

- (BOOL)shouldLaunchViaWorkspace
{
  return (self.options & FBSimulatorLaunchOptionsUseNSWorkspace) == FBSimulatorLaunchOptionsUseNSWorkspace;
}

- (BOOL)shouldConnectBridge
{
  return ((self.options & FBSimulatorLaunchOptionsConnectBridge) == FBSimulatorLaunchOptionsConnectBridge) || self.shouldUseDirectLaunch;
}

#pragma mark Scale

- (NSString *)lastScaleCommandLineSwitchForSimulator:(FBSimulator *)simulator
{
  return [NSString stringWithFormat:@"-SimulatorWindowLastScale-%@", simulator.device.deviceTypeIdentifier];
}

@end
