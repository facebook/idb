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
  return CreateSimulatorSetWithFakeDeviceSetAndLogger(configuration, fakeDeviceSet, nil);
}

FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSetAndLogger(FBSimulatorControlConfiguration *configuration,
                                                             NSObject *fakeDeviceSet,
                                                             id<FBControlCoreLogger> _Nullable logger)
{
  NSError *error = nil;
  FBSimulatorSet *set = [FBSimulatorSet setWithConfiguration:configuration
                                                   deviceSet:(SimDeviceSet *)fakeDeviceSet
                                                    delegate:nil
                                                      logger:logger
                                                       error:&error];
  NSCAssert(set, @"Failed to create the simulator set: %@", error);
  return set;
}

#pragma mark - CheckRuntimeRequirements

BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error)
{
  return [configuration checkRuntimeRequirementsReturningError:error];
}
