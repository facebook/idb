/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction.h"
#import "FBSimulatorInteraction+Private.h"

#import <CoreSimulator/SimDevice.h>

#import "FBInteraction+Private.h"
#import "FBInteraction+Private.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBProcessQuery+Simulators.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorInteraction

+ (instancetype)withSimulator:(FBSimulator *)simulator lifecycle:(FBSimulatorSessionLifecycle *)lifecycle;
{
  FBSimulatorInteraction *interaction = [self new];
  interaction.simulator = simulator;
  interaction.lifecycle = lifecycle;
  return interaction;
}

- (instancetype)bootSimulator
{
  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"--args",
      @"-CurrentDeviceUDID", simulator.udid,
      @"-ConnectHardwareKeyboard", @"0",
      simulator.configuration.lastScaleCommandLineSwitch, simulator.configuration.scaleString,
    ]];
    if (simulator.pool.configuration.deviceSetPath) {
      if (!FBSimulatorControlStaticConfiguration.supportsCustomDeviceSets) {
        return [[[FBSimulatorError describe:@"Cannot use custom Device Set on current platform"] inSimulator:simulator] failBool:error];
      }
      [arguments addObjectsFromArray:@[@"-DeviceSetPath", simulator.pool.configuration.deviceSetPath]];
    }

    id<FBTask> task = [[[[FBTaskExecutor.sharedInstance
      withLaunchPath:simulator.simulatorApplication.binary.path]
      withArguments:[arguments copy]]
      withEnvironmentAdditions:@{FBSimulatorControlSimulatorLaunchEnvironmentMagic : @"YES"}]
      build];

    [lifecycle simulatorWillStart:simulator];
    [task startAsynchronously];

    // Failed to launch the process
    if (task.error) {
      return [[[[FBSimulatorError describe:@"Failed to Launch Simulator Process"] causedBy:task.error] inSimulator:simulator] failBool:error];
    }

    BOOL didBoot = [simulator waitOnState:FBSimulatorStateBooted];
    if (!didBoot) {
      return [[[FBSimulatorError describeFormat:@"Timed out waiting for device to be Booted, got %@", simulator.device.stateString] inSimulator:simulator] failBool:error];
    }

    [lifecycle simulator:simulator didStartWithProcessIdentifier:task.processIdentifier terminationHandle:task];

    return YES;
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  NSParameterAssert(url);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

#pragma mark Private

- (instancetype)binary:(FBSimulatorBinary *)binary interact:(BOOL (^)(id<FBProcessInfo> process, NSError **error))block
{
  NSParameterAssert(binary);
  NSParameterAssert(block);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    id<FBProcessInfo> processInfo = [[[[simulator
      launchInfo]
      launchedProcesses]
      filteredArrayUsingPredicate:[FBProcessQuery processesWithLaunchPath:binary.path]]
      firstObject];

    if (!processInfo) {
      return [[[FBSimulatorError describeFormat:@"Could not find an active process for %@", binary] inSimulator:simulator] failBool:error];
    }
    return block(processInfo, error);
  }];
}

@end
