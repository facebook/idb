/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootStrategy.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDevice+Removed.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import <FBControlCore/FBControlCore.h>

#import "FBBundleDescriptor+Simulator.h"
#import "FBFramebuffer.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHID.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBootVerificationStrategy.h"
#import "FBSimulatorLaunchCtlCommands.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorBootConfiguration (FBSimulatorBootStrategy)

@end

@implementation FBSimulatorBootConfiguration (FBSimulatorBootStrategy)

- (BOOL)shouldUseDirectLaunch
{
  return (self.options & FBSimulatorBootOptionsEnableDirectLaunch) == FBSimulatorBootOptionsEnableDirectLaunch;
}

@end

@interface FBCoreSimulatorBootStrategy : NSObject

@property (nonatomic, strong, readonly) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBSimulatorBootStrategy ()

@property (nonatomic, strong, readonly) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBCoreSimulatorBootStrategy *coreSimulatorStrategy;

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator coreSimulatorStrategy:(FBCoreSimulatorBootStrategy *)coreSimulatorStrategy;

@end

@implementation FBCoreSimulatorBootStrategy

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;

  return self;
}

- (FBFuture<FBSimulatorConnection *> *)performBoot
{
  // Only Boot with CoreSimulator when told to do so. Return early if not.
  if (!self.shouldBootWithCoreSimulator) {
    return [self.simulator connect];
  }
  
  return [[[FBSimulatorHID
    hidForSimulator:self.simulator]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorHID *hid) {
      // Booting is simpler than the Simulator.app launch process since the caller calls CoreSimulator Framework directly.
      // Just pass in the options to ensure that the framebuffer service is registered when the Simulator is booted.
      return [[self bootSimulatorWithConfiguration:self.configuration] mapReplace:hid];
    }]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorHID *hid) {
      // Combine everything into the connection.
      return [self.simulator connectWithHID:hid framebuffer:nil];
    }];
}

- (BOOL)shouldBootWithCoreSimulator
{
  // Always boot with CoreSimulator on Xcode 9
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return YES;
  }
  // Otherwise obey the direct launch config.
  return self.configuration.shouldUseDirectLaunch;
}

- (FBFuture<NSNull *> *)bootSimulatorWithConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  // "Persisting" means for the booted Simulator to live beyond the lifecycle of the process that calls the boot API.
  // This is the default for `simctl which boots the simulator and leaves it booted until 'shutdown' is called.
  // This is also possible in `simctl` if the undocumented `--wait` flag is passed after the Simulator's UDID.
  // If "Direct Launch" is enabled we *do not* want the Simulator to live beyond the lifecycle of the process calling boot
  // as this gives us cleaner teardown semantics for automated scenarios.
  NSDictionary<NSString *, id> * options = @{
    @"persist": @(!configuration.shouldUseDirectLaunch),
    @"env" : configuration.environment ?: @{},
  };

  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  [self.simulator.device bootAsyncWithOptions:options completionQueue:self.simulator.workQueue completionHandler:^(NSError *error){
    if (error) {
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:NSNull.null];
    }
  }];
  return future;
}

@end

@implementation FBSimulatorBootStrategy

+ (instancetype)strategyWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  FBCoreSimulatorBootStrategy *coreSimulatorStrategy = [[FBCoreSimulatorBootStrategy alloc] initWithConfiguration:configuration simulator:simulator];
  return [[FBSimulatorBootStrategy alloc] initWithConfiguration:configuration simulator:simulator coreSimulatorStrategy:coreSimulatorStrategy];
}

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator coreSimulatorStrategy:(FBCoreSimulatorBootStrategy *)coreSimulatorStrategy
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;
  _coreSimulatorStrategy = coreSimulatorStrategy;

  return self;
}

- (FBFuture<NSNull *> *)boot
{
  // Return early depending on Simulator state.
  if (self.simulator.state == FBiOSTargetStateBooted) {
    return FBFuture.empty;
  }
  if (self.simulator.state != FBiOSTargetStateShutdown) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot Boot Simulator when in %@ state", self.simulator.stateString]
      inSimulator:self.simulator]
      failFuture];
  }

  // Boot via CoreSimulator.
  return [[[self.coreSimulatorStrategy
    performBoot]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [self verifySimulatorIsBooted];
    }]
    mapReplace:NSNull.null];
}

- (FBFuture<FBProcessInfo *> *)verifySimulatorIsBooted
{
  FBSimulatorProcessFetcher *processFetcher = self.simulator.processFetcher;
  FBProcessInfo *launchdProcess = [processFetcher launchdProcessForSimDevice:self.simulator.device];
  if (!launchdProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:self.simulator]
      failFuture];
  }
  self.simulator.launchdProcess = launchdProcess;

  // Return early if we're not awaiting services.
  if ((self.configuration.options & FBSimulatorBootOptionsVerifyUsable) != FBSimulatorBootOptionsVerifyUsable) {
    return [FBFuture futureWithResult:launchdProcess];
  }

  // Now wait for the services.
  return [[[FBSimulatorBootVerificationStrategy
    strategyWithSimulator:self.simulator]
    verifySimulatorIsBooted]
    mapReplace:launchdProcess];
}

@end
