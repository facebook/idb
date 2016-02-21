/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessInteraction.h"

#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimulatorError.h"
#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorLaunchCtl.h"
#import "NSRunLoop+SimulatorControlAdditions.h"
#import "FBProcessTerminationStrategy.h"
#import "FBSimulatorEventSink.h"

@implementation FBProcessInteraction

#pragma mark Public

- (FBSimulatorInteraction *)signal:(int)signo
{
  return [self interactWithProcess:^ BOOL (NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    // Confirm that the process has the launchd_sim as a parent process.
    // The interaction should restrict itself to simulator processes so this is a guard
    // to ensure that this interaction can't go around killing random processes.
    pid_t parentProcessIdentifier = [simulator.processQuery parentOf:process.processIdentifier];
    if (parentProcessIdentifier != simulator.launchdSimProcess.processIdentifier) {
      return [[FBSimulatorError
        describeFormat:@"Parent of %@ is not the launchd_sim (%@) it has a pid %d", process.shortDescription, simulator.launchdSimProcess.shortDescription, parentProcessIdentifier]
        failBool:error];
    }

    // Notify the eventSink of the process getting killed, before it is killed.
    // This is done to prevent being marked as an unexpected termination when the
    // detecting of the process getting killed kicks in.
    FBProcessLaunchConfiguration *configuration = simulator.history.processLaunchConfigurations[process];
    if ([configuration isKindOfClass:FBApplicationLaunchConfiguration.class]) {
      [simulator.eventSink applicationDidTerminate:process expected:YES];
    } else if ([configuration isKindOfClass:FBAgentLaunchConfiguration.class]) {
      [simulator.eventSink agentDidTerminate:process expected:YES];
    }

    // Use FBProcessTerminationStrategy to do the actual process killing
    // as it has more intelligent backoff strategies and error messaging.
    NSError *innerError = nil;
    if (![[FBProcessTerminationStrategy withProcessQuery:simulator.processQuery logger:simulator.logger] killProcess:process error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    // Ensure that the Simulator's launchctl knows that the process is gone
    // Killing the process should guarantee that tha Simulator knows that the process has terminated.
    [simulator.logger.debug logFormat:@"Waiting for %@ to be removed from launchctl", process.shortDescription];
    BOOL isGoneFromLaunchCtl = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^ BOOL {
      return ![simulator.launchctl processIsRunningOnSimulator:process error:nil];
    }];
    if (!isGoneFromLaunchCtl) {
      return [[FBSimulatorError
        describeFormat:@"Process %@ did not get removed from launchctl", process.shortDescription]
        failBool:error];
    }
    [simulator.logger.debug logFormat:@"%@ has been removed from launchctl", process.shortDescription];

    return YES;
  }];
}

- (FBSimulatorInteraction *)kill
{
  return [self signal:SIGKILL];
}

#pragma mark Private

- (FBSimulatorInteraction *)interactWithProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBSimulatorInteraction *)withProcess:(FBProcessInfo *)process interact:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  NSParameterAssert(block);

  return [self interactWithBootedSimulator:^BOOL(id interaction, NSError **error, FBSimulator *simulator) {
    return block(error, simulator, process);
  }];
}

@end

@interface FBProcessInteraction_Process : FBProcessInteraction

@property (nonatomic, strong, readonly) FBProcessInfo *process;

@end

@implementation FBProcessInteraction_Process

#pragma mark Initializers

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction simulator:(FBSimulator *)simulator process:(FBProcessInfo *)process
{
  self = [super initWithInteraction:interaction simulator:simulator];
  if (!self) {
    return nil;
  }

  _process = process;
  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBProcessInteraction_Process *interaction = [super copyWithZone:zone];
  interaction->_process = self.process;
  return interaction;
}

#pragma mark Private

- (FBSimulatorInteraction *)interactWithProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  return [self withProcess:self.process interact:block];
}

@end

@interface FBProcessInteraction_BundleID : FBProcessInteraction

@property (nonatomic, strong, readonly) NSString *bundleID;

@end

@implementation FBProcessInteraction_BundleID

#pragma mark Initializers

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction simulator:(FBSimulator *)simulator bundleID:(NSString *)bundleID
{
  self = [super initWithInteraction:interaction simulator:simulator];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBProcessInteraction_BundleID *interaction = [super copyWithZone:zone];
  interaction->_bundleID = self.bundleID;
  return interaction;
}

#pragma mark Private

- (FBSimulatorInteraction *)interactWithProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  NSString *bundleID = self.bundleID;

  return [self interactWithBootedSimulator:^ BOOL (id interaction, NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    FBProcessInfo *process = [simulator runningApplicationWithBundleID:bundleID error:&innerError];
    if (!process) {
      return [[[[FBSimulatorError
        describeFormat:@"Could not find a running application for '%@'", bundleID]
        inSimulator:simulator]
        causedBy:innerError]
        failBool:error];
    }
    return block(error, simulator, process);
  }];
}

@end

@interface FBProcessInteraction_Binary : FBProcessInteraction

@property (nonatomic, strong, readonly) FBSimulatorBinary *binary;

@end

@implementation FBProcessInteraction_Binary

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction simulator:(FBSimulator *)simulator binary:(FBSimulatorBinary *)binary
{
  self = [super initWithInteraction:interaction simulator:simulator];
  if (!self) {
    return nil;
  }

  _binary = binary;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBProcessInteraction_Binary *interaction = [super copyWithZone:zone];
  interaction->_binary = self.binary;
  return interaction;
}

#pragma mark Private

- (FBSimulatorInteraction *)interactWithProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  FBSimulatorBinary *binary = self.binary;

  return [self binary:binary interact:^ BOOL (id interaction, NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    return block(error, simulator, process);
  }];
}

@end

@interface FBProcessInteraction_LastLaunched : FBProcessInteraction

@property (nonatomic, assign, readonly) BOOL application;

@end

@implementation FBProcessInteraction_LastLaunched

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction simulator:(FBSimulator *)simulator application:(BOOL)application
{
  self = [super initWithInteraction:interaction simulator:simulator];
  if (!self) {
    return nil;
  }

  _application = application;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBProcessInteraction_LastLaunched *interaction = [super copyWithZone:zone];
  interaction->_application = self.application;
  return interaction;
}

#pragma mark Private

- (FBSimulatorInteraction *)interactWithProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  return [self interactWithBootedSimulator:^ BOOL (FBProcessInteraction_LastLaunched *interaction, NSError **error, FBSimulator *simulator) {
    FBProcessInfo *process = interaction.application ? simulator.history.lastLaunchedApplicationProcess : simulator.history.lastLaunchedAgentProcess;
    if (!process) {
      return [[[FBSimulatorError
        describe:@"Could not find a last launched process"]
        inSimulator:simulator]
        failBool:error];
    }
    return block(error, simulator, process);
  }];
}

@end

@implementation FBSimulatorInteraction (FBProcessInteraction)

- (FBProcessInteraction *)process:(FBProcessInfo *)process
{
  return [[FBProcessInteraction_Process alloc] initWithInteraction:self.interaction simulator:self.simulator process:process];
}

- (FBProcessInteraction *)applicationProcess:(FBSimulatorApplication *)application
{
  return [[FBProcessInteraction_BundleID alloc] initWithInteraction:self.interaction simulator:self.simulator bundleID:application.bundleID];
}

- (FBProcessInteraction *)applicationProcessWithBundleID:(NSString *)bundleID
{
  return [[FBProcessInteraction_BundleID alloc] initWithInteraction:self.interaction simulator:self.simulator bundleID:bundleID];
}

- (FBProcessInteraction *)agentProcess:(FBSimulatorBinary *)binary
{
  return [[FBProcessInteraction_Binary alloc] initWithInteraction:self.interaction simulator:self.simulator binary:binary];
}

- (FBProcessInteraction *)lastLaunchedApplication
{
  return [[FBProcessInteraction_LastLaunched alloc] initWithInteraction:self.interaction simulator:self.simulator application:YES];
}

@end
