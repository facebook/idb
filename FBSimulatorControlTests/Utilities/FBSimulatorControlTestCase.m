/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlTestCase.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>

#import "FBSimulatorControlNotificationAssertion.h"

@interface FBSimulatorControlTestCase ()

@property (nonatomic, strong, readwrite) FBSimulatorControl *control;
@property (nonatomic, strong, readwrite) FBSimulatorControlNotificationAssertion *notificationAssertion;

@end

@implementation FBSimulatorControlTestCase

- (FBSimulatorManagementOptions)managementOptions
{
  return FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart |
         FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart |
         FBSimulatorManagementOptionsDeleteOnFree;
}

- (void)setUp
{
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    namePrefix:nil
    bucket:0
    options:[self managementOptions]];

  self.control = [[FBSimulatorControl alloc] initWithConfiguration:configuration];
  self.notificationAssertion = [FBSimulatorControlNotificationAssertion new];
}

- (void)tearDown
{
  [self.control.simulatorPool killManagedSimulatorsWithError:nil];
  self.control = nil;
}

@end
