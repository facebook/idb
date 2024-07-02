/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorNotificationUpdateStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <FBControlCore/FBControlCore.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBSimulator.h"
#import "FBSimulatorSet.h"
#import "FBSimulator+Private.h"

@interface FBSimulatorNotificationUpdateStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, strong, readwrite) FBCoreSimulatorNotifier *notifier;

@end

@implementation FBSimulatorNotificationUpdateStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSet:(FBSimulatorSet *)set
{
  FBSimulatorNotificationUpdateStrategy *strategy = [[self alloc] initWithSet:set];
  [strategy startNotifyingOfStateChanges];
  return strategy;
}

- (instancetype)initWithSet:(FBSimulatorSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;

  return self;
}

- (void)dealloc
{
  [self.notifier terminate];
  self.notifier = nil;
}

#pragma mark Private

- (void)startNotifyingOfStateChanges
{
  __weak typeof(self) weakSelf = self;
  self.notifier = [FBCoreSimulatorNotifier notifierForSet:self.set queue:self.set.workQueue block:^(NSDictionary *info) {
    SimDevice *device = info[@"device"];
    if (!device) {
      return;
    }
    NSNumber *newStateNumber = info[@"new_state"];
    if (!newStateNumber) {
      return;
    }
    [weakSelf device:device didChangeState:newStateNumber.unsignedIntegerValue];
  }];
}

- (void)device:(SimDevice *)device didChangeState:(FBiOSTargetState)state
{
  FBSimulator *simulator = [self.set simulatorWithUDID:device.UDID.UUIDString];
  if (!simulator) {
    return;
  }
  [simulator disconnectWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout logger:simulator.logger];
  [_set.delegate targetUpdated:simulator inTargetSet:simulator.set];
}

@end
