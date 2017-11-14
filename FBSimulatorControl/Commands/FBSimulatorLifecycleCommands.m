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
#import "FBSimulatorEventRelay.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"
#import "FBSimulatorTerminationStrategy.h"

@interface FBSimulatorLifecycleCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

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

- (BOOL)bootWithError:(NSError **)error
{
  return [self boot:FBSimulatorBootConfiguration.defaultConfiguration error:error];
}

- (BOOL)boot:(FBSimulatorBootConfiguration *)configuration error:(NSError **)error
{
  return [[FBSimulatorBootStrategy
    strategyWithConfiguration:configuration simulator:self.simulator]
    bootWithError:error];
}

- (FBFuture<NSNull *> *)shutdown
{
  return [[self.simulator.set killSimulator:self.simulator] mapReplace:NSNull.null];
}

#pragma mark Erase

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  if (!self.simulator.pool) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as there is no pool associated" errorOut:error];
  }
  if (!self.simulator.isAllocated) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as this Simulator has not been allocated" errorOut:error];
  }
  return [self.simulator.pool freeSimulator:self.simulator error:error];
}

- (BOOL)eraseWithError:(NSError **)error
{
  return [self.simulator.set eraseSimulator:self.simulator error:error];
}

#pragma mark States

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBControlCoreGlobalConfiguration.regularTimeout];
}

- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout
{
  FBSimulator *simulator = self.simulator;
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return simulator.state == state;
  }];
}

- (BOOL)waitOnState:(FBSimulatorState)state error:(NSError **)error
{
  if (![self waitOnState:state]) {
    return [[[FBSimulatorError
      describeFormat:@"Simulator was not in expected %@ state, got %@", FBSimulatorStateStringFromState(self.simulator.state), self.simulator.stateString]
      inSimulator:self.simulator]
      failBool:error];
  }
  return YES;
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
  if (simulator.eventRelay.connection) {
    return simulator.eventRelay.connection;
  }
  if (simulator.state != FBSimulatorStateBooted) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot connect to Simulator in state %@", simulator.stateString]
      inSimulator:simulator]
      fail:error];
  }

  FBSimulatorConnection *connection = [[FBSimulatorConnection alloc] initWithSimulator:simulator framebuffer:nil hid:nil];
  [simulator.eventSink connectionDidConnect:connection];
  return connection;
}

- (BOOL)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  FBSimulatorConnection *connection = simulator.eventRelay.connection;
  if (!connection) {
    [logger.debug logFormat:@"Simulator %@ does not have an active connection", simulator.shortDescription];
    return YES;
  }

  [logger.debug logFormat:@"Simulator %@ has a connection %@, stopping & wait with timeout %f", simulator.shortDescription, connection, timeout];
  NSDate *date = NSDate.date;
  if (![connection terminateWithTimeout:timeout]) {
    return [[[[FBSimulatorError
      describeFormat:@"Simulator connection %@ did not teardown in less than %f seconds", connection, timeout]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }
  [logger.debug logFormat:@"Simulator connection %@ torn down in %f seconds", connection, [NSDate.date timeIntervalSinceDate:date]];
  return YES;
}

#pragma mark Framebuffer

- (nullable FBFramebuffer *)framebufferWithError:(NSError **)error
{
  return [[self
    connectWithError:error]
    connectToFramebuffer:error];
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
