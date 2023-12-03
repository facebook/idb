/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMRestorableDevice.h"

#import "FBDeviceControlError.h"

static NSString *const UnknownValue = @"unknown";

@implementation FBAMRestorableDevice

@synthesize calls = _calls;
@synthesize logger = _logger;
@synthesize restorableDevice = _restorableDevice;

- (instancetype)initWithCalls:(AMDCalls)calls restorableDevice:(AMRestorableDeviceRef)restorableDevice allValues:(NSDictionary<NSString *, id> *)allValues workQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _restorableDevice = restorableDevice;
  _allValues = allValues;
  _workQueue = workQueue;
  _asyncQueue = asyncQueue;
  _logger = logger;

  return self;
}

#pragma mark FBiOSTargetInfo

- (NSString *)uniqueIdentifier
{
  return [self.allValues[FBDeviceKeyUniqueChipID] stringValue];
}

- (NSString *)udid
{
  return UnknownValue;
}

- (NSString *)name
{
  return self.allValues[FBDeviceKeyDeviceName];
}

- (FBiOSTargetState)state
{
  AMRestorableDeviceState deviceState = self.calls.RestorableDeviceGetState(self.restorableDevice);
  switch (deviceState) {
    case AMRestorableDeviceStateDFU:
      return FBiOSTargetStateDFU;
    case AMRestorableDeviceStateRecovery:
      return FBiOSTargetStateRecovery;
    case AMRestorableDeviceStateRestoreOS:
      return FBiOSTargetStateRestoreOS;
    case AMRestorableDeviceStateBootedOS:
      return FBiOSTargetStateBooted;
    default:
      return FBiOSTargetStateUnknown;
  }
}

- (FBDeviceType *)deviceType
{
  NSString *productString = self.allValues[FBDeviceKeyProductType];
  return [FBDeviceType genericWithName:productString];
}


- (NSArray<FBArchitecture> *)architectures
{
    return @[UnknownValue];
}

- (FBiOSTargetType)targetType
{
  return FBiOSTargetTypeDevice;
}

- (FBOSVersion *)osVersion
{
  return [FBOSVersion genericWithName:UnknownValue];
}

- (NSDictionary<NSString *, id> *)extendedInformation
{
  return @{
    @"device": self.allValues,
  };
}

#pragma mark FBDevice

- (NSString *)buildVersion
{
  return UnknownValue;
}

- (NSString *)productVersion
{
  return UnknownValue;
}

- (AMDeviceRef)amDeviceRef
{
  return NULL;
}

- (AMRecoveryModeDeviceRef)recoveryModeDeviceRef
{
  return self.calls.RestorableDeviceGetRecoveryModeDevice(self.restorableDevice);
}

- (FBDeviceActivationState)activationState
{
  return FBDeviceActivationStateUnknown;
}

#pragma mark Public

// AMRestorableGetStringForState, is a private function so we can't get to it.
// Instead it's a very simple implementation so we just re-implement it.
+ (FBiOSTargetState)targetStateForDeviceState:(AMRestorableDeviceState)state
{
  switch (state) {
    case AMRestorableDeviceStateDFU:
      return FBiOSTargetStateDFU;
    case AMRestorableDeviceStateRecovery:
      return FBiOSTargetStateRecovery;
    case AMRestorableDeviceStateRestoreOS:
      return FBiOSTargetStateRestoreOS;
    case AMRestorableDeviceStateBootedOS:
      return FBiOSTargetStateBooted;
    default:
      return FBiOSTargetStateUnknown;
  }
}

- (void)setRestorableDevice:(AMRestorableDeviceRef)restorableDevice
{
  AMDeviceRef oldRestorableDevice = _restorableDevice;
  if (restorableDevice) {
    CFRetain(restorableDevice);
  }
  if (oldRestorableDevice) {
    CFRelease(oldRestorableDevice);
  }
  _restorableDevice = restorableDevice;
}

- (AMRestorableDeviceRef)restorableDevice
{
  return _restorableDevice;
}

@end
