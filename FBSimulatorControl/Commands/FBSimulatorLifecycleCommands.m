/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLifecycleCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <AppKit/AppKit.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBSimulator.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBootStrategy.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"

const int OPEN_URL_RETRIES = 2;

@interface FBSimulatorLifecycleCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readwrite, nullable) FBSimulatorHID *hid;
@property (nonatomic, strong, readwrite, nullable) FBSimulatorBridge *bridge;

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

- (FBFuture<NSNull *> *)boot:(FBSimulatorBootConfiguration *)configuration
{
  return [FBSimulatorBootStrategy boot:self.simulator withConfiguration:configuration];
}

#pragma mark FBPowerCommands

- (FBFuture<NSNull *> *)shutdown
{
  return [[self.simulator.set shutdown:self.simulator] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)reboot
{
  return [[self
    shutdown]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      return [self boot:FBSimulatorBootConfiguration.defaultConfiguration];
    }];
}

#pragma mark Erase

- (FBFuture<NSNull *> *)erase
{
  return [[self.simulator.set erase:self.simulator] mapReplace:NSNull.null];
}

#pragma mark States

- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state
{
  return FBiOSTargetResolveState(self.simulator, state);
}

- (FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state
{
  return [FBCoreSimulatorNotifier resolveLeavesState:state forSimDevice:self.simulator.device];
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
  FBBundleDescriptor *applicationBundle = FBXcodeConfiguration.simulatorApp;
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

- (FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger
{
  NSDate *date = NSDate.date;
  return [[[self
    terminateConnections]
    timeout:timeout waitingFor:@"Simulator connections to teardown"]
    onQueue:self.simulator.workQueue map:^(id _) {
      [logger.debug logFormat:@"Simulator connections torn down in %f seconds", [NSDate.date timeIntervalSinceDate:date]];
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)terminateConnections
{
  FBSimulatorHID *hid = self.hid;
  FBSimulatorBridge *bridge = self.bridge;
  return [[FBFuture
    futureWithFutures:@[
      (hid ? [hid disconnect] : FBFuture.empty),
      (bridge ? [bridge disconnect] : FBFuture.empty),
    ]]
    onQueue:self.simulator.workQueue chain:^(FBFuture *_) {
      // Nullify
      self.hid = nil;
      self.bridge = nil;
      return FBFuture.empty;
    }];
}

#pragma mark Bridge

- (FBFuture<FBSimulatorBridge *> *)connectToBridge
{
  if (self.bridge) {
    return [FBFuture futureWithResult:self.bridge];
  }

  return [[FBSimulatorBridge
    bridgeForSimulator:self.simulator]
    onQueue:self.simulator.workQueue map:^(FBSimulatorBridge *bridge) {
      self.bridge = bridge;
      return bridge;
    }];
}

#pragma mark Framebuffer

- (FBFuture<FBFramebuffer *> *)connectToFramebuffer
{
  FBSimulator *simulator = self.simulator;
  return [FBFuture
    onQueue:simulator.workQueue resolveValue:^(NSError **error) {
      return [FBFramebuffer mainScreenSurfaceForSimulator:simulator logger:simulator.logger error:error];
    }];
}

#pragma mark Bridge

- (FBFuture<FBSimulatorHID *> *)connectToHID
{
  if (self.hid) {
    return [FBFuture futureWithResult:self.hid];
  }
  return [[FBSimulatorHID
    hidForSimulator:self.simulator]
    onQueue:self.simulator.workQueue map:^(FBSimulatorHID *hid) {
      self.hid = hid;
      return hid;
    }];
}

#pragma mark URLs

- (FBFuture<NSNull *> *)openURL:(NSURL *)url
{
  NSParameterAssert(url);
  NSError *error = nil;

  int retry = 0;
  do {
    // Retry openURL 2 times to alleviate Rosetta startup slowness.
    if ([self.simulator.device openURL:url error:&error]) {
      return [FBFuture futureWithResult:[NSNull null]];
    }
    retry++;
  } while (retry <= OPEN_URL_RETRIES);

  return [[[FBSimulatorError
    describeFormat:@"Failed to open URL %@ on simulator %@", url, self.simulator]
    causedBy:error]
    failFuture];
}

@end
