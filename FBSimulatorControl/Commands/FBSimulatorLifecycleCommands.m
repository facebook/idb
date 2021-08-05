/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLifecycleCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <AppKit/AppKit.h>

#import "FBBundleDescriptor+Simulator.h"
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
  // We cannot 'focus' a SimulatorApp for the non-default device set.
  NSString *deviceSetPath = self.simulator.customDeviceSetPath;
  if (deviceSetPath) {
    return [[FBSimulatorError
      describeFormat:@"Focusing on the Simulator App for a simulator in a custom device set (%@) is not supported", deviceSetPath]
      failFuture];
  }
  
  // Find the running instances of SimulatorApp.
  NSArray<NSRunningApplication *> *apps = NSWorkspace.sharedWorkspace.runningApplications;
  NSPredicate *simulatorAppPredicate = [NSPredicate predicateWithBlock:^(NSRunningApplication *application, NSDictionary<NSString *,id> *__) {
    return [application.bundleIdentifier isEqualToString:@"com.apple.iphonesimulator"];
  }];
  NSArray<NSRunningApplication *> *simulatorApps = [apps filteredArrayUsingPredicate:simulatorAppPredicate];

  // If we have no SimulatorApp running then we can instead launch one in a focused state
  if (simulatorApps.count == 0) {
    NSError *error = nil;
    NSRunningApplication *simulatorApp = [FBSimulatorLifecycleCommands launchSimulatorApplicationForDefaultDeviceSetWithError:&error];
    if (!simulatorApp) {
      return [FBFuture futureWithError:error];
    }
    return FBFuture.empty;
  }

  // Multiple apps, we don't know which to select.
  if (simulatorApps.count > 1) {
    return [[FBSimulatorError
      describeFormat:@"More than one SimulatorApp %@ running, focus is ambiguous", [FBCollectionInformation oneLineDescriptionFromArray:simulatorApps]]
      failFuture];
  }
  
  // Otherwise we have a single Simulator App to activate.
  NSRunningApplication *simulatorApp = simulatorApps.firstObject;
  if (![simulatorApp activateWithOptions:NSApplicationActivateIgnoringOtherApps]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to focus %@", simulatorApp]
      failFuture];
  }

  return FBFuture.empty;
}

+ (NSRunningApplication *)launchSimulatorApplicationForDefaultDeviceSetWithError:(NSError **)error
{
  // Obtain the location of the SimulatorApp
  FBBundleDescriptor *applicationBundle = FBBundleDescriptor.xcodeSimulator;
  NSURL *applicationURL = [NSURL fileURLWithPath:applicationBundle.path];

  // We only want to ever connect to the default SimulatorApp, including re-activating it rather than creating a new instance.
  NSError *innerError = nil;
  NSRunningApplication *application = [NSWorkspace.sharedWorkspace
    launchApplicationAtURL:applicationURL
    options:NSWorkspaceLaunchDefault
    configuration:@{}
    error:&innerError];

  if (!application) {
    return [[[FBSimulatorError
      describe:@"Failed to launch SimulatorApp"]
      causedBy:innerError]
      fail:error];
  }

  return application;
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
    return [[FBSimulatorError
      describeFormat:@"Cannot connect to Simulator in state %@", simulator.stateString]
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
