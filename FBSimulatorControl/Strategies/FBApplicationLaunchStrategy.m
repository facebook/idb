/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"
#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBApplicationLaunchStrategy.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimDeviceWrapper.h"
#import "FBProcessLaunchConfiguration+Helpers.h"

@interface FBApplicationLaunchStrategy ()

@property (nonnull, nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBApplicationLaunchStrategy

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self){
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark Public

- (FBProcessInfo *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  NSError *innerError = nil;
  FBSimulatorApplication *application = [simulator installedApplicationWithBundleID:appLaunch.bundleID error:&innerError];
  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"App %@ can't be launched as it isn't installed", appLaunch.bundleID]
      causedBy:innerError]
      inSimulator:simulator]
      fail:error];
  }

  // This check confirms that if there's a currently running process for the given Bundle ID it doesn't match one that has been recently launched.
  // Since the Background Modes of a Simulator can cause an Application to be launched independently of our usage of CoreSimulator,
  // it's possible that application processes will come to life before `launchApplication` is called, if it has been previously killed.
  FBProcessInfo *process = [simulator runningApplicationWithBundleID:appLaunch.bundleID error:&innerError];
  if (process && [simulator.history.launchedApplicationProcesses containsObject:process]) {
    return [[[[FBSimulatorError
      describeFormat:@"App %@ can't be launched as is running (%@)", appLaunch.bundleID, process.shortDescription]
      causedBy:innerError]
      inSimulator:simulator]
      fail:error];
  }

  NSDictionary *options = [appLaunch simDeviceLaunchOptionsWithStdOut:nil stdErr:nil];
  if (!options) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  process = [simulator.simDeviceWrapper launchApplicationWithID:appLaunch.bundleID options:options error:&innerError];
  if (!process) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to launch application %@", appLaunch]
      causedBy:innerError]
      inSimulator:simulator]
      fail:error];
  }
  [simulator.eventSink applicationDidLaunch:appLaunch didStart:process];
  return process;
}

@end
