/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorsManager.h"
#import <FBSimulatorControl/FBSimulatorControl.h>

@interface FBSimulatorsManager ()
@property (nonatomic, strong, readonly) FBSimulatorControl *simulatorControl;
@end

@implementation FBSimulatorsManager

- (instancetype)initWithSimulatorControlConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  self = [super init];

  if (!self) {
    return nil;
  }
  _simulatorControl = [FBSimulatorControl withConfiguration:configuration error:nil];
  return self;
}

- (FBFuture<FBSimulator *> *)createSimulatorWithName:(nullable NSString *)name withOSName:(nullable NSString *)osName
{
  FBSimulatorConfiguration *simulatorConfiguration = [FBSimulatorConfiguration defaultConfiguration];
  if (name) {
    simulatorConfiguration = [simulatorConfiguration withDeviceModel:name];
  }
  if (osName) {
    simulatorConfiguration = [simulatorConfiguration withOSNamed:osName];
  }
  return [_simulatorControl.set createSimulatorWithConfiguration:simulatorConfiguration];
}

- (FBFuture<NSArray<NSString *> *> *)deleteAll
{
  return [_simulatorControl.set deleteAll];
}

- (FBFuture<NSString *> *)deleteSimulator:(NSString *)udid
{
  FBSimulator *simulatorToDelete;
  for (FBSimulator *simulator in [_simulatorControl.set allSimulators]) {
    if ([simulator.udid isEqualToString:udid]) {
      simulatorToDelete = simulator;
    }
  }
  return [_simulatorControl.set deleteSimulator:simulatorToDelete];
}

@end
