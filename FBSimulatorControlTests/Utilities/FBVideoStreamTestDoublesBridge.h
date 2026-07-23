/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorSet;

NS_ASSUME_NONNULL_BEGIN

/**
 Creates an FBSimulatorSet using a fake SimDeviceSet (NSObject double).
 SimDeviceSet is a private framework class unavailable in Swift.
 */
FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSet(
  FBSimulatorControlConfiguration *configuration,
  NSObject *fakeDeviceSet);

/**
 Wraps checkRuntimeRequirementsReturningError: because the FBSimulatorConfiguration (CoreSimulator) category
 is not visible in Swift due to forward-declared private framework types (SimDevice, SimRuntime).
 */
BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
