/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceCommands.h"

FBDeviceActivationState const FBDeviceActivationStateUnknown = @"Unknown";
FBDeviceActivationState const FBDeviceActivationStateUnactivated = @"Unactivated";
FBDeviceActivationState const FBDeviceActivationStateActivated = @"Activated";


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
