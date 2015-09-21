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

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState+Queries.h"
#import "FBSimulatorSessionState.h"
#import "FBTaskExecutor.h"

#import <CoreSimulator/SimDevice.h>

NSTimeInterval const FBSimulatorInteractionDefaultTimeout = 30;

@implementation FBSimulatorSessionInteraction

#pragma mark Public

+ (instancetype)builderWithSession:(FBSimulatorSession *)session
{
  FBSimulatorSessionInteraction *interaction = [self new];
  interaction.session = session;
  interaction.interactions = [NSMutableArray array];
  return interaction;
}

- (instancetype)bootSimulator
{
  FBSimulator *simulator = self.session.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    id<FBTask> task = [FBTaskExecutor.sharedInstance
      taskWithLaunchPath:simulator.simulatorApplication.binary.path
      arguments:@[@"--args", @"-CurrentDeviceUDID", simulator.udid]];

    [lifecycle simulatorWillStart:simulator];
    [task startAsynchronously];

    // Failed to launch the process
    if (task.error) {
      return [FBSimulatorControl failBoolWithError:task.error description:@"Failed to Launch Simulator Process" errorOut:error];
    }

    BOOL didBoot = [simulator waitOnState:FBSimulatorStateBooted];
    if (!didBoot) {
      NSString *description = [NSString stringWithFormat:@"Timed out waiting for device to be Booted, got %@", simulator.device.stateString];
      if (task.error) {
        return [FBSimulatorControl failBoolWithError:task.error description:description errorOut:error];
      }
      return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
    }

    [lifecycle simulator:simulator didStartWithProcessIdentifier:task.processIdentifier terminationHandle:task];

    return YES;
  }];
}

- (instancetype)installApplication:(FBSimulatorApplication *)application
{
  FBSimulator *simulator = self.session.simulator;

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    if (![simulator.device installApplication:[NSURL URLWithString:application.path] withOptions:@{@"CFBundleIdentifier" : application.bundleID} error:error]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to install Application" errorOut:error];
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
      return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [FBSimulatorSessionInteraction launchOptionsForLaunchConfiguration:appLaunch stdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
    }

    NSInteger processIdentifier = [simulator.device launchApplicationWithID:appLaunch.application.bundleID options:options error:&innerError];
    if (processIdentifier <= 0) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to launch application" errorOut:error];
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

  return [self application:application interact:^ BOOL (NSInteger processIdentifier, NSError **error) {
    [lifecycle applicationWillTerminate:application];
    int returnCode = kill(processIdentifier, signo);
    if (returnCode != 0) {
      NSString *description = [NSString stringWithFormat:@"SIGKILL of Application %@ of PID %ld failed", application, processIdentifier];
      return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
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
      return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [FBSimulatorSessionInteraction launchOptionsForLaunchConfiguration:agentLaunch stdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
    }

    NSInteger processIdentifier = [simulator.device
      spawnWithPath:agentLaunch.agentBinary.path
      options:options
      terminationHandler:NULL
      error:&innerError];

    if (processIdentifier <= 0) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to start Agent" errorOut:error];
    }

    [lifecycle agentDidLaunch:agentLaunch didStartWithProcessIdentifier:processIdentifier stdOut:stdOut stdErr:stdErr];
    return YES;
  }];
}

- (instancetype)killAgent:(FBSimulatorBinary *)agent
{
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self interact:^ BOOL (NSError **error) {
    FBUserLaunchedProcess *state = [lifecycle.currentState processForBinary:agent];
    if (!state) {
      NSString *description = [NSString stringWithFormat:@"Could not kill agent %@ as it is not running", agent];
      return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
    }

    [lifecycle agentWillTerminate:agent];
    if (!kill(state.processIdentifier, SIGKILL)) {
      NSString *description = [NSString stringWithFormat:@"SIGKILL of Agent %@ of PID %ld failed", agent, state.processIdentifier];
      return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
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
      return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

- (id<FBSimulatorInteraction>)build
{
  return [FBSimulatorInteraction chainInteractions:[self.interactions copy]];
}

- (BOOL)performInteractionWithError:(NSError **)error
{
  return [[self build] performInteractionWithError:error];
}

#pragma mark Private

+ (BOOL)createHandlesForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfiguration stdOut:(NSFileHandle **)stdOut stdErr:(NSFileHandle **)stdErr error:(NSError **)error
{
  if (launchConfiguration.stdOutPath) {
    if (![NSFileManager.defaultManager createFileAtPath:launchConfiguration.stdOutPath contents:NSData.data attributes:nil]) {
      NSString *message = [NSString stringWithFormat:@"Could not create stdout at path '%@' for config '%@'", launchConfiguration.stdOutPath, launchConfiguration];
      return [FBSimulatorControl failBoolWithErrorMessage:message errorOut:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:launchConfiguration.stdOutPath];
    if (!fileHandle) {
      NSString *message = [NSString stringWithFormat:@"Could not file handle for stdout at path '%@' for config '%@'", launchConfiguration.stdOutPath, launchConfiguration];
      return [FBSimulatorControl failBoolWithErrorMessage:message errorOut:error];
    }
    *stdOut = fileHandle;
  }
  if (launchConfiguration.stdErrPath) {
    if (![NSFileManager.defaultManager createFileAtPath:launchConfiguration.stdErrPath contents:NSData.data attributes:nil]) {
      NSString *message = [NSString stringWithFormat:@"Could not create stderr at path '%@' for config '%@'", launchConfiguration.stdErrPath, launchConfiguration];
      return [FBSimulatorControl failBoolWithErrorMessage:message errorOut:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:launchConfiguration.stdErrPath];
    if (!fileHandle) {
      NSString *message = [NSString stringWithFormat:@"Could not file handle for stderr at path '%@' for config '%@'", launchConfiguration.stdErrPath, launchConfiguration];
      return [FBSimulatorControl failBoolWithErrorMessage:message errorOut:error];
    }
    *stdErr = fileHandle;
  }
  return YES;
}

+ (NSDictionary *)launchOptionsForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfiguration stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr error:(NSError **)error
{
  NSMutableDictionary *options = [@{
    @"arguments" : launchConfiguration.arguments,
    @"environment" : launchConfiguration.environment
  } mutableCopy];

  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  return [options copy];
}

- (instancetype)interact:(BOOL (^)(NSError **error))block
{
  NSParameterAssert(block);
  return [self addInteraction:[FBSimulatorInteraction_Block interactionWithBlock:block]];
}

- (instancetype)application:(FBSimulatorApplication *)application interact:(BOOL (^)(NSInteger processIdentifier, NSError **error))block
{
  return [self interact:^ BOOL (NSError **error) {
    FBUserLaunchedProcess *processState = [self.session.state processForBinary:application.binary];
    if (!processState) {
      NSString *message = [NSString stringWithFormat:@"Could not find an active process for %@", application];
      return [FBSimulatorControl failBoolWithErrorMessage:message errorOut:error];
    }
    return block(processState.processIdentifier, error);
  }];
}

- (instancetype)addInteraction:(id<FBSimulatorInteraction>)interaction
{
  [self.interactions addObject:interaction];
  return self;
}

- (instancetype)retry:(NSUInteger)retries
{
  NSParameterAssert(self.interactions.count > 0);
  NSParameterAssert(retries > 1);

  NSUInteger interactionIndex = self.interactions.count - 1;
  id<FBSimulatorInteraction> interaction = self.interactions[interactionIndex];

  id<FBSimulatorInteraction> retryInteraction = [FBSimulatorInteraction_Block interactionWithBlock:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    for (NSUInteger index = 0; index < retries; index++) {
      if ([interaction performInteractionWithError:&innerError]) {
        return YES;
      }
    }
    NSString *description = [NSString stringWithFormat:@"Failed interaction after %ld retries", retries];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
  }];

  [self.interactions replaceObjectAtIndex:interactionIndex withObject:retryInteraction];
  return self;
}

@end
