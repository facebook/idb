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
  return [@(self.UniqueID) stringValue];
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
  return FBiOSTargetStateUnknown;
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
      @"UniqueID": @(self.UniqueID),
      @"LocationID": @(self.LocationID),
      @"ChipID": @(self.ChipID),
      @"DeviceClass": @(self.DeviceClass),
      @"ProductType": self.ProductString,
    },
  };
}

#pragma mark Public

// AMRestorableGetStringForState, is a private function so we can't get to it.
// Instead it's a very simple implementation so we just re-implement it.
+ (NSString *)stringForState:(AMRestorableDeviceState)state
{
  switch (state) {
    case AMRestorableDeviceStateDFU:
      return @"DFU";
    case AMRestorableDeviceStateRecovery:
      return @"Recovery";
    case AMRestorableDeviceStateRestoreOS:
      return @"Recovery";
    case AMRestorableDeviceStateBootedOS:
      return @"BootedOS";
    default:
      return @"Unknown";
  }
}

#pragma mark Private

- (int)UniqueID
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


@end
