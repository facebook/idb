/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLifecycleCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <AppKit/AppKit.h>

#import "FBSimulator.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBootStrategy.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorMutableState.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"
#import "FBSimulatorTerminationStrategy.h"

@interface FBSimulatorLifecycleCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readwrite) FBSimulatorConnection *connection;

@end

@implementation FBSimulatorLifecycleCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark Boot/Shutdown

- (FBFuture<NSNull *> *)boot
{
  return [self bootWithConfiguration:FBSimulatorBootConfiguration.defaultConfiguration];
}

- (FBFuture<NSNull *> *)bootWithConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  return [[FBSimulatorBootStrategy
    strategyWithConfiguration:configuration simulator:self.simulator]
    boot];
}

- (FBFuture<NSNull *> *)shutdown
{
  return [[self.simulator.set killSimulator:self.simulator] mapReplace:NSNull.null];
}

#pragma mark Erase

- (FBFuture<NSNull *> *)freeFromPool
{
  if (!self.simulator.pool) {
    return [[FBSimulatorError
      describe:@"Cannot free from pool as there is no pool associated"]
      failFuture];
  }
  if (!self.simulator.isAllocated) {
    return [[FBSimulatorError
      describe:@"Cannot free from pool as this Simulator has not been allocated"]
      failFuture];
  }
  return [self.simulator.pool freeSimulator:self.simulator];
}

- (FBFuture<NSNull *> *)erase
{
  return [[self.simulator.set eraseSimulator:self.simulator] mapReplace:NSNull.null];
}

#pragma mark States

- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state
{
  FBSimulator *simulator = self.simulator;
  return [[FBFuture onQueue:simulator.workQueue resolveWhen:^ BOOL {
    return simulator.state == state;
  }] mapReplace:NSNull.null];
}

#pragma mark Focus

- (BOOL)focusWithError:(NSError **)error
{
  NSArray *apps = NSWorkspace.sharedWorkspace.runningApplications;
  NSPredicate *matchingPid = [NSPredicate predicateWithFormat:@"processIdentifier = %@", @(self.simulator.containerApplication.processIdentifier)];
  NSRunningApplication *app = [apps filteredArrayUsingPredicate:matchingPid].firstObject;
  if (!app) {
    return [[FBSimulatorError describeFormat:@"Simulator application for %@ is not running", self.simulator.udid] failBool:error];
  }

  return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

#pragma mark Connection

- (nullable FBSimulatorConnection *)connectWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  if (self.connection) {
    return self.connection;
  }
  if (simulator.state != FBiOSTargetStateBooted) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot connect to Simulator in state %@", simulator.stateString]
      inSimulator:simulator]
      fail:error];
  }

  FBSimulatorConnection *connection = [[FBSimulatorConnection alloc] initWithSimulator:simulator framebuffer:nil hid:nil];
  self.connection = connection;
  [simulator.eventSink connectionDidConnect:connection];
  return connection;
}

- (FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger
{
  FBSimulator *simulator = self.simulator;
  FBSimulatorConnection *connection = self.connection;
  if (!connection) {
    [logger.debug logFormat:@"Simulator %@ does not have an active connection", simulator.shortDescription];
    return [FBFuture futureWithResult:NSNull.null];
  }

  NSDate *date = NSDate.date;
  [logger.debug logFormat:@"Simulator %@ has a connection %@, stopping & wait with timeout %f", simulator.shortDescription, connection, timeout];
  return [[[connection
    terminate]
    timeout:timeout waitingFor:@"The Simulator Connection to teardown"]
    onQueue:self.simulator.workQueue map:^(id _) {
      [logger.debug logFormat:@"Simulator connection %@ torn down in %f seconds", connection, [NSDate.date timeIntervalSinceDate:date]];
      [self.simulator.eventSink connectionDidDisconnect:connection expected:YES];
      return NSNull.null;
    }];
}

#pragma mark Bridge

- (FBFuture<FBSimulatorBridge *> *)connectToBridge
{
  NSError *error = nil;
  FBSimulatorConnection *connection = [self connectWithError:&error];
  if (!connection) {
    return [FBFuture futureWithError:error];
  }
  return [connection connectToBridge];
}

#pragma mark Framebuffer

- (FBFuture<FBFramebuffer *> *)connectToFramebuffer
{
  NSError *error = nil;
  FBSimulatorConnection *connection = [self connectWithError:&error];
  if (!connection) {
    return [FBFuture futureWithError:error];
  }
  return [connection connectToFramebuffer];
}

#pragma mark URLs

- (BOOL)openURL:(NSURL *)url error:(NSError **)error
{
  NSParameterAssert(url);
  NSError *innerError = nil;
  if (![self.simulator.device openURL:url error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to open URL %@ on simulator %@", url, self.simulator]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

@end
