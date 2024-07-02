/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceCommands.h"

FBDeviceActivationState const FBDeviceActivationStateUnknown = @"Unknown";
FBDeviceActivationState const FBDeviceActivationStateUnactivated = @"Unactivated";
FBDeviceActivationState const FBDeviceActivationStateActivated = @"Activated";

FBDeviceKey const FBDeviceKeyChipID = @"ChipID";
FBDeviceKey const FBDeviceKeyDeviceClass = @"DeviceClass";
FBDeviceKey const FBDeviceKeyDeviceName = @"DeviceName";
FBDeviceKey const FBDeviceKeyLocationID = @"LocationID";
FBDeviceKey const FBDeviceKeyProductType = @"ProductType";
FBDeviceKey const FBDeviceKeySerialNumber = @"SerialNumber";
FBDeviceKey const FBDeviceKeyUniqueChipID = @"UniqueChipID";
FBDeviceKey const FBDeviceKeyUniqueDeviceID = @"UniqueDeviceID";
FBDeviceKey const FBDeviceKeyCPUArchitecture = @"CPUArchitecture";
FBDeviceKey const FBDeviceKeyBuildVersion = @"BuildVersion";
FBDeviceKey const FBDeviceKeyProductVersion = @"ProductVersion";
FBDeviceKey const FBDeviceKeyActivationState = @"ActivationState";
FBDeviceKey const FBDeviceKeyIsPaired = @"IsPaired";

FBDeviceActivationState FBDeviceActivationStateCoerceFromString(NSString *activationState)
{
  if ([activationState isEqualToString:@"Unactivated"]) {
    return FBDeviceActivationStateUnactivated;
  }
  if ([activationState isEqualToString:@"Activated"]) {
    return FBDeviceActivationStateActivated;
  }
  return FBDeviceActivationStateUnknown;
}
