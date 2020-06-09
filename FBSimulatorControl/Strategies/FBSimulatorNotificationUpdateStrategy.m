/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorNotificationUpdateStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <FBControlCore/FBControlCore.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSet.h"

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
  self.notifier = [FBCoreSimulatorNotifier notifierForSet:self.set queue:dispatch_get_main_queue() block:^(NSDictionary *info) {
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
  FBiOSTargetQuery *query = [FBiOSTargetQuery udid:device.UDID.UUIDString];
  NSArray<FBSimulator *> *simulators = [self.set query:query];
  if (simulators.count != 1) {
    return;
  }
  FBSimulator *simulator = simulators.firstObject;
  [simulator.eventSink didChangeState:state];

  // Update State in response to boot/shutdown
  if (state == FBiOSTargetStateBooted) {
    [self fetchLaunchdSimInfoFromBootOfSimulator:simulator];
  }
  if (state == FBiOSTargetStateShutdown || state == FBiOSTargetStateShuttingDown) {
    [self discardLaunchdSimInfoFromShutdownOfSimulator:simulator];
  }
  [_set.delegate targetUpdated:simulator inTargetSet:simulator.set];
}

- (void)fetchLaunchdSimInfoFromBootOfSimulator:(FBSimulator *)simulator
{
  // We already have launchd_sim info, don't bother fetching.
  if (simulator.launchdProcess) {
    return;
  }

  FBProcessInfo *launchdSim = [self.processFetcher launchdProcessForSimDevice:simulator.device];
  if (!launchdSim) {
    return;
  }
  [simulator.eventSink simulatorDidLaunch:launchdSim];
}

- (void)discardLaunchdSimInfoFromShutdownOfSimulator:(FBSimulator *)simulator
{
  // Don't look at the application if we know if we don't consider the Simulator boot.
  FBProcessInfo *launchdProcess = simulator.launchdProcess;
  if (!launchdProcess) {
    return;
  }

  // Notify of Simulator Termination.
  [simulator.eventSink simulatorDidTerminate:launchdProcess expected:NO];
}

- (FBSimulatorProcessFetcher *)processFetcher
{
  return self.set.processFetcher;
}

@end
