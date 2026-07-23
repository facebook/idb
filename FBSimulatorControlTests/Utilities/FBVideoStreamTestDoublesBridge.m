/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStreamTestDoublesBridge.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <objc/message.h>

#pragma mark - CreateSimulatorSetWithFakeDeviceSet

FBSimulatorSet *CreateSimulatorSetWithFakeDeviceSet(FBSimulatorControlConfiguration *configuration,
                                                    NSObject *fakeDeviceSet)
{
  SEL selector = NSSelectorFromString(@"setWithConfiguration:deviceSet:delegate:logger:reporter:");
  return ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
    FBSimulatorSet.class,
    selector,
    configuration,
    fakeDeviceSet,
    nil,
    nil,
    nil
  );
}

#pragma mark - CheckRuntimeRequirements

BOOL CheckRuntimeRequirements(FBSimulatorConfiguration *configuration, NSError * _Nullable * _Nullable error)
{
  return [configuration checkRuntimeRequirementsReturningError:error];
}
