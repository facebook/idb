/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetProvider.h"

#import <FBDeviceControl/FBDeviceControl.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBiOSTargetProvider

+ (FBiOSTargetType)targetTypeForUDID:(NSString *)udid
{
  const FBiOSTargetType types[3] = {FBiOSTargetTypeDevice, FBiOSTargetTypeSimulator, FBiOSTargetTypeLocalMac};
  for (NSUInteger idx = 0; idx < 3; idx++) {
    FBiOSTargetType type = types[idx];
    NSPredicate *devicePredicate = [FBiOSTargetPredicates udidsOfType:type];
    if ([devicePredicate evaluateWithObject:udid]) {
      return type;
    }
  }
  return FBiOSTargetTypeNone;
}

+ (nullable id<FBiOSTarget>)targetWithUDID:(NSString *)udid logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter error:(NSError **)error
{
  FBiOSTargetType targetType = [self targetTypeForUDID:udid];
  if (targetType == FBiOSTargetTypeNone) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not valid UDID", udid]
      fail:error];
  }

  // Get a simulator if one was requested
  if (targetType == FBiOSTargetTypeSimulator) {
    [FBCrashLogNotifier.sharedInstance startListening:YES];
    NSString *deviceSetPath = [NSUserDefaults.standardUserDefaults stringForKey:@"-device-set-path"];
    FBSimulatorControlConfiguration *configuration =
    [FBSimulatorControlConfiguration configurationWithDeviceSetPath:deviceSetPath options:0 logger:logger reporter:reporter];
    FBSimulatorControl *simulatorControl = [FBSimulatorControl withConfiguration:configuration error:error];
    if (!simulatorControl) {
      return nil;
    }

    id<FBiOSTarget> simulator = [[simulatorControl.set query:[FBiOSTargetQuery udid:udid]] firstObject];
    if (!simulator) {
      return [[FBControlCoreError
        describeFormat:@"Simulator with udid %@ could not be found in device set %@", udid, deviceSetPath]
        fail:error];
    }
    return simulator;
  }

  // Get a device if one was requested
  if (targetType == FBiOSTargetTypeDevice) {
    FBDeviceSet *deviceSet =  [FBDeviceSet defaultSetWithLogger:logger error:error];
    if (!deviceSet) {
      return nil;
    }
    id<FBiOSTarget> device = [[deviceSet query:[FBiOSTargetQuery udid:udid]] firstObject];
    if (!device) {
      return [[FBControlCoreError
        describeFormat:@"Device with udid %@ could not be found", udid]
        fail:error];
    }
    return device;
  }

  // Get a mac device if one was requested
  if (targetType == FBiOSTargetTypeLocalMac) {
    FBMacDevice *mac = [[FBMacDevice alloc] initWithLogger:logger];
    if (![mac.udid isEqual:udid]) {
      return nil;
    }
    return mac;
  }
  return nil;
}

@end
