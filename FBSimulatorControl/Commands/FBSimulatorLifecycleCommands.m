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

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBSimulator+Helpers.h"
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

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
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

- (BOOL)bootSimulatorWithError:(NSError **)error
{
  return [self bootSimulator:FBSimulatorBootConfiguration.defaultConfiguration error:error];
}

- (BOOL)bootSimulator:(FBSimulatorBootConfiguration *)configuration error:(NSError **)error
{
  return [[FBSimulatorBootStrategy
    strategyWithConfiguration:configuration simulator:self.simulator]
    boot:error];
}

- (BOOL)shutdownSimulatorWithError:(NSError **)error
{
  return [self.simulator.set killSimulator:self.simulator error:error];
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

#pragma mark Subprocesses

- (BOOL)terminateSubprocess:(FBProcessInfo *)process error:(NSError **)error
{
  NSParameterAssert(process);
    return [[FBSimulatorSubprocessTerminationStrategy
      strategyWithSimulator:self.simulator]
      terminate:process error:error];
}

@end
