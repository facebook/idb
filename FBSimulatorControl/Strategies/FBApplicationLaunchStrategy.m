/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import "FBApplicationLaunchStrategy.h"
#import "FBSimulatorApplicationOperation.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"
#import "FBProcessLaunchConfiguration+Simulator.h"
#import "FBSimulatorLaunchCtlCommands.h"

@interface FBApplicationLaunchStrategy ()

@property (nonnull, nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBApplicationLaunchStrategy_Bridge : FBApplicationLaunchStrategy

@end

@interface FBApplicationLaunchStrategy_CoreSimulator : FBApplicationLaunchStrategy

@end

@implementation FBApplicationLaunchStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator useBridge:(BOOL)useBridge;
{
  Class strategyClass = useBridge ? FBApplicationLaunchStrategy_CoreSimulator.class : FBApplicationLaunchStrategy_CoreSimulator.class;
  return [[strategyClass alloc] initWithSimulator:simulator];
}

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [self strategyWithSimulator:simulator useBridge:NO];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self){
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

- (FBFuture<FBSimulatorApplicationOperation *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  FBSimulator *simulator = self.simulator;
  NSError *innerError = nil;
  FBInstalledApplication *application = [[simulator installedApplicationWithBundleID:appLaunch.bundleID] await:&innerError];
  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"App %@ can't be launched as it isn't installed", appLaunch.bundleID]
      causedBy:innerError]
      inSimulator:simulator]
      failFuture];
  }

  // This check confirms that if there's a currently running process for the given Bundle ID.
  // Since the Background Modes of a Simulator can cause an Application to be launched independently of our usage of CoreSimulator,
  // it's possible that application processes will come to life before `launchApplication` is called, if it has been previously killed.
  FBProcessInfo *process = [[simulator runningApplicationWithBundleID:appLaunch.bundleID] await:&innerError];
  if (process) {
    return [[[[FBSimulatorError
      describeFormat:@"App %@ can't be launched as is running (%@)", appLaunch.bundleID, process.shortDescription]
      causedBy:innerError]
      inSimulator:simulator]
      failFuture];
  }

  // Make the stdout file.
  NSError *error = nil;
  FBDiagnostic *stdOutDiagnostic = nil;
  if (![appLaunch createStdOutDiagnosticForSimulator:simulator diagnosticOut:&stdOutDiagnostic error:&error]) {
    return [FBSimulatorError failFutureWithError:error];
  }
  // Make the stderr file.
  FBDiagnostic *stdErrDiagnostic = nil;
  if (![appLaunch createStdErrDiagnosticForSimulator:simulator diagnosticOut:&stdErrDiagnostic error:&error]) {
    return [FBSimulatorError failFutureWithError:error];
  }

  // Actually launch the Application, getting the Process Info.
  FBFuture<NSNumber *> *launchFuture = [self launchApplication:appLaunch stdOutPath:stdOutDiagnostic.asPath stdErrPath:stdErrDiagnostic.asPath];
  if (launchFuture.error) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to launch application %@", appLaunch]
      causedBy:launchFuture.error]
      inSimulator:simulator]
      failFuture];
  }

  // Make the Operation.
  return [[FBSimulatorApplicationOperation
    operationWithSimulator:simulator configuration:appLaunch launchFuture:launchFuture]
    onQueue:self.simulator.workQueue notifyOfCompletion:^(FBFuture *resolved) {
      if (!resolved.result) {
        return;
      }
      // Report the diagnostics to the event sink.
      if (stdOutDiagnostic) {
        [simulator.eventSink diagnosticAvailable:stdOutDiagnostic];
      }
      if (stdErrDiagnostic) {
        [simulator.eventSink diagnosticAvailable:stdErrDiagnostic];
      }
    }];
}

- (FBFuture<FBSimulatorApplicationOperation *> *)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  // Kill the Application if it exists. Don't bother killing the process if it doesn't exist
  FBSimulator *simulator = self.simulator;
  return [[[simulator
    runningApplicationWithBundleID:appLaunch.bundleID]
    onQueue:self.simulator.workQueue fmap:^(FBProcessInfo *process) {
      return process
        ? [[FBSimulatorSubprocessTerminationStrategy strategyWithSimulator:simulator] terminate:process]
        : [FBFuture futureWithResult:NSNull.null];
    }]
    onQueue:simulator.workQueue fmap:^FBFuture *(NSNull *result) {
      return [simulator launchApplication:appLaunch];
    }];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

- (BOOL)uninstallApplication:(NSString *)bundleID error:(NSError **)error
{
  // Confirm the app is suitable to be uninstalled.
  FBSimulator *simulator = self.simulator;
  if ([simulator isSystemApplicationWithBundleID:bundleID error:nil]) {
    return [[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it is a system Application", bundleID]
      inSimulator:simulator]
      failBool:error];
  }
  NSError *innerError = nil;
  if (![[simulator installedApplicationWithBundleID:bundleID] await:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it isn't installed", bundleID]
      causedBy:innerError]
      inSimulator:simulator]
      failBool:error];
  }
  // Kill the app if it's running
  [[simulator killApplicationWithBundleID:bundleID] await:nil];
  // Then uninstall for real.
  if (![simulator.device uninstallApplication:bundleID withOptions:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to uninstall '%@'", bundleID]
      causedBy:innerError]
      inSimulator:simulator]
      failBool:error];
  }
  return YES;
}

@end

@implementation FBApplicationLaunchStrategy_Bridge

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  // The Bridge must be connected in order for the launch to work.
  NSError *innerError = nil;
  FBSimulator *simulator = self.simulator;
  FBSimulatorBridge *bridge = [[simulator connectWithError:&innerError] connectToBridge:&innerError];
  if (!bridge) {
    return [[[FBSimulatorError
      describeFormat:@"Could not connect bridge to Simulator in order to launch application %@", appLaunch]
      causedBy:innerError]
      failFuture];
  }

  // Launch the Application.
  pid_t processIdentifier = [bridge launch:appLaunch stdOutPath:stdErrPath stdErrPath:stdOutPath error:&innerError];
  if (processIdentifier < 2) {
    return [FBFuture futureWithError:innerError];
  }
  return [FBFuture futureWithResult:@(processIdentifier)];
}

@end

@implementation FBApplicationLaunchStrategy_CoreSimulator

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBSimulator *simulator = self.simulator;
  NSDictionary<NSString *, id> *options = [appLaunch
    simDeviceLaunchOptionsWithStdOutPath:[self translateAbsolutePath:stdOutPath toPathRelativeTo:simulator.dataDirectory]
    stdErrPath:[self translateAbsolutePath:stdErrPath toPathRelativeTo:simulator.dataDirectory]
    waitForDebugger:appLaunch.waitForDebugger];

  FBMutableFuture<NSNumber *> *future = [FBMutableFuture future];
  [simulator.device launchApplicationAsyncWithID:appLaunch.bundleID options:options completionQueue:simulator.workQueue completionHandler:^(NSError *error, pid_t pid){
    if (error) {
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:@(pid)];
    }
  }];
  return future;
}

- (NSString *)translateAbsolutePath:(NSString *)absolutePath toPathRelativeTo:(NSString *)referencePath
{
  if (![absolutePath hasPrefix:@"/"]) {
    return absolutePath;
  }
  // When launching an application with a custom stdout/stderr path, `SimDevice` uses the given path relative
  // to the Simulator's data directory. From the Framework's consumer point of view this might not be the
  // wanted behaviour. To work around it, we construct a path relative to the Simulator's data directory
  // using `..` until we end up in the absolute path outside the Simulator's data directory.
  NSString *translatedPath = @"";
  for (NSUInteger index = 0; index < referencePath.pathComponents.count; index++) {
    translatedPath = [translatedPath stringByAppendingPathComponent:@".."];
  }
  return [translatedPath stringByAppendingPathComponent:absolutePath];
}

@end
