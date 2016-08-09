/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Lifecycle.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessFetcher+Simulators.h"
#import "FBProcessTerminationStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorBootStrategy.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorTerminationStrategy.h"

@implementation FBSimulatorInteraction (Lifecycle)

- (instancetype)bootSimulator
{
  return [self bootSimulator:FBSimulatorLaunchConfiguration.defaultConfiguration];
}

- (instancetype)bootSimulator:(FBSimulatorLaunchConfiguration *)configuration
{
  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBSimulatorBootStrategy withConfiguration:configuration simulator:simulator] boot:error];
  }];
}

- (instancetype)shutdownSimulator
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [simulator.set killSimulator:simulator error:error];
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  NSParameterAssert(url);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)terminateSubprocess:(FBProcessInfo *)process
{
  NSParameterAssert(process);

  return [self process:process interact:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBSimulatorSubprocessTerminationStrategy forSimulator:simulator]
      terminate:process error:error];
  }];
}

@end
