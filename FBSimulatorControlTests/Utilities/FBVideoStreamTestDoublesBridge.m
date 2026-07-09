/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStreamTestDoublesBridge.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#pragma mark - CreateSimulatorSetWithFakeDeviceSet

FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSet(FBSimulatorControlConfiguration *configuration,
                                                    NSObject *fakeDeviceSet)
{
  return [FBSimulatorSet setWithConfiguration:configuration
                                    deviceSet:(SimDeviceSet *)fakeDeviceSet
                                     delegate:nil
                                       logger:nil
                                     reporter:nil];
}

#pragma mark - CheckRuntimeRequirements

BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error)
{
  return [configuration checkRuntimeRequirementsReturningError:error];
}
