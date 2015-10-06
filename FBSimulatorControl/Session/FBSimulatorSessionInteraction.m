/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionInteraction.h"
#import "FBSimulatorSessionInteraction+Private.h"

#import <CoreSimulator/SimDevice.h>

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
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState+Queries.h"
#import "FBSimulatorSessionState.h"
#import "FBSimulatorWindowTiler.h"
#import "FBSimulatorWindowTilingStrategy.h"
#import "FBSimulatorVideoRecorder.h"
#import "FBTaskExecutor.h"

NSTimeInterval const FBSimulatorInteractionDefaultTimeout = 30;

@implementation FBSimulatorSessionInteraction

#pragma mark Public

+ (instancetype)builderWithSession:(FBSimulatorSession *)session
{
  FBSimulatorSessionInteraction *interaction = [self new];
  interaction.session = session;
  return interaction;
}

- (instancetype)bootSimulator
{
  FBManagedSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
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

    id<FBTask> task = [FBTaskExecutor.sharedInstance
      taskWithLaunchPath:simulator.simulatorApplication.binary.path
      arguments:[arguments copy]];

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

- (instancetype)tileSimulator:(id<FBSimulatorWindowTilingStrategy>)tilingStrategy;
{
  FBSimulator *simulator = self.session.simulator;

  return [self interact:^ BOOL (NSError **error) {
    FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler withSimulator:simulator strategy:tilingStrategy];
    NSError *innerError = nil;
    if (CGRectIsNull([tiler placeInForegroundWithError:&innerError])) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)tileSimulator
{
  return [self tileSimulator:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:self.session.simulator]];
}

- (instancetype)recordVideo
{
  FBSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    FBSimulatorVideoRecorder *recorder = [FBSimulatorVideoRecorder forSimulator:simulator logger:nil];
    NSString *path = [lifecycle pathForStorage:@"video" ofExtension:@"mp4"];

    NSError *innerError = nil;
    if (![recorder startRecordingToFilePath:path error:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to start recording video"] inSimulator:simulator] failBool:error];
    }

    [lifecycle associateEndOfSessionCleanup:recorder];
    [lifecycle sessionDidGainDiagnosticInformationWithName:@"video" data:path];
    return YES;
  }];
}

- (instancetype)installApplication:(FBSimulatorApplication *)application
{
  FBSimulator *simulator = self.session.simulator;

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    if (![simulator.device installApplication:[NSURL URLWithString:application.path] withOptions:@{@"CFBundleIdentifier" : application.bundleID} error:error]) {
      return [[[FBSimulatorError describe:@"Failed to install Application"] causedBy:innerError] failBool:error];
    }

    return YES;
  }];
}

- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  FBSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![FBSimulatorSessionInteraction createHandlesForLaunchConfiguration:appLaunch stdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [FBSimulatorSessionInteraction launchOptionsForLaunchConfiguration:appLaunch stdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSInteger processIdentifier = [simulator.device launchApplicationWithID:appLaunch.application.bundleID options:options error:&innerError];
    if (processIdentifier <= 0) {
      return [[[[FBSimulatorError describe:@"Failed to launch application"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
    [lifecycle applicationDidLaunch:appLaunch didStartWithProcessIdentifier:processIdentifier stdOut:stdOut stdErr:stdErr];
    return YES;

  }];
}

- (instancetype)killApplication:(FBSimulatorApplication *)application
{
  return [self signal:SIGKILL application:application];
}

- (instancetype)signal:(int)signo application:(FBSimulatorApplication *)application
{
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;
  FBSimulator *simulator = self.session.simulator;

  return [self application:application interact:^ BOOL (NSInteger processIdentifier, NSError **error) {
    [lifecycle applicationWillTerminate:application];
    int returnCode = kill(processIdentifier, signo);
    if (returnCode != 0) {
      return [[[FBSimulatorError describeFormat:@"SIGKILL of Application %@ of PID %ld failed", application, processIdentifier] inSimulator:simulator] failBool:error];
    }
    return YES;
  }];
}

- (instancetype)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch
{
  FBSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![FBSimulatorSessionInteraction createHandlesForLaunchConfiguration:agentLaunch stdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [FBSimulatorSessionInteraction launchOptionsForLaunchConfiguration:agentLaunch stdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSInteger processIdentifier = [simulator.device
      spawnWithPath:agentLaunch.agentBinary.path
      options:options
      terminationHandler:NULL
      error:&innerError];

    if (processIdentifier <= 0) {
      return [[[[FBSimulatorError describe:@"Failed to start Agent"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }

    [lifecycle agentDidLaunch:agentLaunch didStartWithProcessIdentifier:processIdentifier stdOut:stdOut stdErr:stdErr];
    return YES;
  }];
}

- (instancetype)killAgent:(FBSimulatorBinary *)agent
{
  FBSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    FBUserLaunchedProcess *state = [lifecycle.currentState processForBinary:agent];
    if (!state) {
      return [[[FBSimulatorError describeFormat:@"Could not kill agent %@ as it is not running", agent] inSimulator:simulator] failBool:error];
    }

    [lifecycle agentWillTerminate:agent];
    if (!kill(state.processIdentifier, SIGKILL)) {
      return [[[FBSimulatorError describeFormat:@"SIGKILL of Agent %@ of PID %ld failed", agent, state.processIdentifier] inSimulator:simulator] failBool:error];
    }
    return YES;
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  FBSimulator *simulator = self.session.simulator;

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulato %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

#pragma mark Private

+ (BOOL)createHandlesForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfiguration stdOut:(NSFileHandle **)stdOut stdErr:(NSFileHandle **)stdErr error:(NSError **)error
{
  if (launchConfiguration.stdOutPath) {
    if (![NSFileManager.defaultManager createFileAtPath:launchConfiguration.stdOutPath contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError describeFormat:
        @"Could not create stdout at path '%@' for config '%@'",
        launchConfiguration.stdOutPath,
        launchConfiguration
      ] failBool:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:launchConfiguration.stdOutPath];
    if (!fileHandle) {
      return [[FBSimulatorError describeFormat:
        @"Could not file handle for stdout at path '%@' for config '%@'",
        launchConfiguration.stdOutPath,
        launchConfiguration
      ] failBool:error];
    }
    *stdOut = fileHandle;
  }
  if (launchConfiguration.stdErrPath) {
    if (![NSFileManager.defaultManager createFileAtPath:launchConfiguration.stdErrPath contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError describeFormat:
        @"Could not create stderr at path '%@' for config '%@'",
        launchConfiguration.stdErrPath,
        launchConfiguration
      ] failBool:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:launchConfiguration.stdErrPath];
    if (!fileHandle) {
      return [[FBSimulatorError describeFormat:
        @"Could not file handle for stderr at path '%@' for config '%@'",
        launchConfiguration.stdErrPath,
        launchConfiguration
      ] failBool:error];
    }
    *stdErr = fileHandle;
  }
  return YES;
}

+ (NSDictionary *)launchOptionsForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfiguration stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr error:(NSError **)error
{
  NSMutableDictionary *options = [@{
    @"arguments" : launchConfiguration.arguments,
    // iOS 7 Launch fails if the environment is empty, put some nothing in the environment for it.
    @"environment" : launchConfiguration.environment.count ? launchConfiguration.environment:  @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"}
  } mutableCopy];

  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  return [options copy];
}

- (instancetype)application:(FBSimulatorApplication *)application interact:(BOOL (^)(NSInteger processIdentifier, NSError **error))block
{
  FBSimulatorSession *session = self.session;
  FBSimulator *simulator = self.session.simulator;

  return [self interact:^ BOOL (NSError **error) {
    FBUserLaunchedProcess *processState = [session.state processForBinary:application.binary];
    if (!processState) {
      return [[[FBSimulatorError describeFormat:@"Could not find an active process for %@", application] inSimulator:simulator] failBool:error];
    }
    return block(processState.processIdentifier, error);
  }];
}

@end
