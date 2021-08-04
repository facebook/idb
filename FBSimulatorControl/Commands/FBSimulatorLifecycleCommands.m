/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

#pragma mark FBPowerCommands

- (FBFuture<NSNull *> *)shutdown
{
  return [[self.simulator.set killSimulator:self.simulator] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)reboot
{
  return [[self
    shutdown]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      return [self boot];
    }];
}

#pragma mark Erase

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

- (FBFuture<NSNull *> *)focus
{
  NSString *deviceSetPath = self.simulator.customDeviceSetPath;
  if (deviceSetPath) {
    return [[FBSimulatorError
      describeFormat:@"Focusing on the Simulator App for a simulator in a custom device set (%@) is not supported", deviceSetPath]
      failFuture];
  }
  NSArray<NSRunningApplication *> *apps = NSWorkspace.sharedWorkspace.runningApplications;
  NSPredicate *simulatorAppPredicate = [NSPredicate predicateWithBlock:^(NSRunningApplication *application, NSDictionary<NSString *,id> *__) {
    return [application.bundleIdentifier isEqualToString:@"com.apple.iphonesimulator"];
  }];
  NSArray<NSRunningApplication *> *simulatorApps = [apps filteredArrayUsingPredicate:simulatorAppPredicate];
  if (simulatorApps.count > 1) {
    return [[FBSimulatorError
      describeFormat:@"More than one SimulatorApp %@ running, focus is ambiguous", [FBCollectionInformation oneLineDescriptionFromArray:simulatorApps]]
      failFuture];
  }
  if (simulatorApps.count == 0) {
    return [[FBSimulatorError
      describe:@"No SimulatorApp running, nothing to focus"]
      failFuture];
  }
  NSRunningApplication *simulatorApp = simulatorApps.firstObject;
  if (![simulatorApp activateWithOptions:NSApplicationActivateIgnoringOtherApps]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to focus %@", simulatorApp]
      failFuture];
  }
  return FBFuture.empty;
}

#pragma mark Connection

- (FBFuture<FBSimulatorConnection *> *)connect
{
  return [self connectWithHID:nil framebuffer:nil];
}

- (FBFuture<FBSimulatorConnection *> *)connectWithHID:(FBSimulatorHID *)hid framebuffer:(FBFramebuffer *)framebuffer
{
  FBSimulator *simulator = self.simulator;
  if (self.connection) {
    return [FBFuture futureWithResult:self.connection];
  }
  if (simulator.state != FBiOSTargetStateBooted && simulator.state != FBiOSTargetStateBooting) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot connect to Simulator in state %@", simulator.stateString]
      inSimulator:simulator]
      failFuture];
  }

  FBSimulatorConnection *connection = [[FBSimulatorConnection alloc] initWithSimulator:simulator framebuffer:framebuffer hid:hid];
  self.connection = connection;
  return [FBFuture futureWithResult:connection];
}

- (FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger
{
  FBSimulator *simulator = self.simulator;
  FBSimulatorConnection *connection = self.connection;
  if (!connection) {
    [logger.debug logFormat:@"Simulator %@ does not have an active connection", simulator.description];
    return FBFuture.empty;
  }

  NSDate *date = NSDate.date;
  [logger.debug logFormat:@"Simulator %@ has a connection %@, stopping & wait with timeout %f", simulator.description, connection, timeout];
  return [[[connection
    terminate]
    timeout:timeout waitingFor:@"The Simulator Connection to teardown"]
    onQueue:self.simulator.workQueue map:^(id _) {
      [logger.debug logFormat:@"Simulator connection %@ torn down in %f seconds", connection, [NSDate.date timeIntervalSinceDate:date]];
      return NSNull.null;
    }];
}

#pragma mark Bridge

- (FBFuture<FBSimulatorBridge *> *)connectToBridge
{
  return [[self
    connect]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToBridge];
    }];
}

#pragma mark Framebuffer

- (FBFuture<FBFramebuffer *> *)connectToFramebuffer
{
  return [[self
    connect]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToFramebuffer];
    }];
}

#pragma mark URLs

- (FBFuture<NSNull *> *)openURL:(NSURL *)url
{
  NSParameterAssert(url);
  NSError *error = nil;
  if (![self.simulator.device openURL:url error:&error]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to open URL %@ on simulator %@", url, self.simulator]
      causedBy:error]
      failFuture];
  }
  return [FBFuture futureWithResult:[NSNull null]];
}

@end
