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

- (FBFuture<NSNull *> *)bootSimulatorWithConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  // "Persisting" means that the booted Simulator should live beyond the lifecycle of the process that calls the boot API.
  // The inverse of this is `FBSimulatorBootOptionsTieToProcessLifecycle`, which means that the Simulator should shutdown when the process that calls the boot API dies.
  //
  // The default behaviour for `simctl` is to 'persist'; the Simulator is left booted until 'shutdown' is called, even after the simctl process dies.
  // `simctl` has the option to 'tie to process lifecycle', if the undocumented `--wait` flag is passed after the Simulator's UDID.
  //
  // If `FBSimulatorBootOptionsTieToProcessLifecycle` is enabled we *do not* want the Simulator to live beyond the lifecycle of the process calling boot.
  // This behaviour is useful for automated scenarios, where terminating the process that performs the boot gives us clean teardown semantics, without the need to call 'shutdown'.
  BOOL persist = (configuration.options & FBSimulatorBootOptionsTieToProcessLifecycle) != FBSimulatorBootOptionsTieToProcessLifecycle;
  NSDictionary<NSString *, id> * options = @{
    @"persist": @(persist),
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
    return [[FBSimulatorError
      describeFormat:@"Cannot Boot Simulator when in %@ state", self.simulator.stateString]
      failFuture];
  }

  // Boot via CoreSimulator.
  return [[self.coreSimulatorStrategy
    performBoot]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [self verifySimulatorIsBooted];
    }];
}

- (FBFuture<NSNull *> *)verifySimulatorIsBooted
{
  // Return early if we're not awaiting services.
  if ((self.configuration.options & FBSimulatorBootOptionsVerifyUsable) != FBSimulatorBootOptionsVerifyUsable) {
    return FBFuture.empty;
  }

  // Now wait for the services.
  return [[FBSimulatorBootVerificationStrategy
    strategyWithSimulator:self.simulator]
    verifySimulatorIsBooted];
}

@end
