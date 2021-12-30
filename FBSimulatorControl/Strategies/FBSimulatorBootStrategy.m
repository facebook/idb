/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBootVerificationStrategy.h"

@implementation FBSimulatorBootStrategy

#pragma mark Initializers

+ (FBFuture<NSNull *> *)boot:(FBSimulator *)simulator withConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  // Return early depending on Simulator state.
  if (simulator.state == FBiOSTargetStateBooted) {
    return FBFuture.empty;
  }
  if (simulator.state != FBiOSTargetStateShutdown) {
    return [[FBSimulatorError
      describeFormat:@"Cannot Boot Simulator when in %@ state", simulator.stateString]
      failFuture];
  }

  // Boot via CoreSimulator.
  return [[self
    performSimulatorBoot:simulator withConfiguration:configuration]
    onQueue:simulator.workQueue fmap:^(id _) {
      return [self verifySimulatorIsBooted:simulator withConfiguration:configuration];
    }];
}

#pragma mark Private

+ (FBFuture<NSNull *> *)verifySimulatorIsBooted:(FBSimulator *)simulator withConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  // Return early if the option to verify boot is not set..
  if ((configuration.options & FBSimulatorBootOptionsVerifyUsable) != FBSimulatorBootOptionsVerifyUsable) {
    return FBFuture.empty;
  }

  // Otherwise actually perform the boot verification.
  return [FBSimulatorBootVerificationStrategy verifySimulatorIsBooted:simulator];
}

+ (FBFuture<NSNull *> *)performSimulatorBoot:(FBSimulator *)simulator withConfiguration:(FBSimulatorBootConfiguration *)configuration
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
  [simulator.device bootAsyncWithOptions:options completionQueue:simulator.workQueue completionHandler:^(NSError *error){
    if (error) {
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:NSNull.null];
    }
  }];
  return future;
}

@end
