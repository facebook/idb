/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMRestorableDevice.h"

static NSString *const UnknownValue = @"unknown";

@implementation FBAMRestorableDevice

- (instancetype)initWithCalls:(AMDCalls)calls restorableDevice:(AMRestorableDeviceRef)restorableDevice
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _restorableDevice = restorableDevice;

  return self;
}

#pragma mark FBiOSTargetInfo

- (NSString *)uniqueIdentifier
{
  return [@(self.UniqueChipID) stringValue];
}

- (NSString *)udid
{
  return UnknownValue;
}

- (NSString *)name
{
  return CFBridgingRelease(self.calls.RestorableDeviceCopyUserFriendlyName(self.restorableDevice));
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
  NSString *productString = CFBridgingRelease(self.calls.RestorableDeviceCopyProductString(self.restorableDevice));
  return [FBDeviceType genericWithName:productString];
}

- (FBArchitecture)architecture
{
  return UnknownValue;
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
    @"device": @{
      @"ChipID": @(self.ChipID),
      @"DeviceClass": @(self.DeviceClass),
      @"LocationID": @(self.LocationID),
      @"ProductType": self.ProductString,
      @"SerialNumber": self.SerialNumber,
      @"UniqueChipID": @(self.UniqueChipID),
    },
  };
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

#pragma mark Private

- (int)UniqueChipID
{
  return self.calls.RestorableDeviceGetECID(self.restorableDevice);
}

- (int)LocationID
{
  return self.calls.RestorableDeviceGetLocationID(self.restorableDevice);
}

- (int)ChipID
{
  return self.calls.RestorableDeviceGetChipID(self.restorableDevice);
}

- (int)DeviceClass
{
  return self.calls.RestorableDeviceGetDeviceClass(self.restorableDevice);
}

- (int)ProductType
{
  return self.calls.RestorableDeviceGetProductType(self.restorableDevice);
}

- (NSString *)ProductString
{
  return CFBridgingRelease(self.calls.RestorableDeviceCopyProductString(self.restorableDevice));
}

- (NSString *)SerialNumber
{
  return CFBridgingRelease(self.calls.RestorableDeviceCopySerialNumber(self.restorableDevice));
}

@end
