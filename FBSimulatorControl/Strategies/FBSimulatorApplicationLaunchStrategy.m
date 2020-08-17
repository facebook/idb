/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import "FBSimulatorApplicationLaunchStrategy.h"
#import "FBSimulatorApplicationOperation.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"
#import "FBProcessLaunchConfiguration+Simulator.h"
#import "FBSimulatorLaunchCtlCommands.h"

@interface FBSimulatorApplicationLaunchStrategy ()

@property (nonnull, nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBSimulatorApplicationLaunchStrategy_Bridge : FBSimulatorApplicationLaunchStrategy

@end

@interface FBSimulatorApplicationLaunchStrategy_CoreSimulator : FBSimulatorApplicationLaunchStrategy

@end

@implementation FBSimulatorApplicationLaunchStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
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
  return [[[[FBFuture futureWithFutures:@[
      [self ensureApplicationIsInstalled:appLaunch.bundleID],
      [self confirmApplicationLaunchState:appLaunch.bundleID launchMode:appLaunch.launchMode],
    ]]
    onQueue:simulator.workQueue fmap:^(id _) {
      return [appLaunch.output createIOForTarget:simulator];
    }]
    onQueue:simulator.workQueue fmap:^(FBProcessIO *io) {
      return [FBFuture futureWithFutures:@[
          [io.stdOut providedThroughFile],
          [io.stdErr providedThroughFile],
      ]];
    }]
    onQueue:simulator.workQueue fmap:^ FBFuture<FBSimulatorApplicationOperation *> * (NSArray<id<FBProcessFileOutput>> *outputs) {
      id<FBProcessFileOutput> stdOut = outputs[0];
      id<FBProcessFileOutput> stdErr = outputs[1];

      FBFuture<NSNumber *> *launch = [self launchApplication:appLaunch stdOut:stdOut stdErr:stdErr];
      return [FBSimulatorApplicationOperation operationWithSimulator:simulator configuration:appLaunch stdOut:stdOut stdErr:stdErr launchFuture:launch];
    }];
}

#pragma mark Private

- (FBFuture<NSNumber *> *)ensureApplicationIsInstalled:(NSString *)bundleID
{
  return [[[self.simulator
    installedApplicationWithBundleID:bundleID]
    mapReplace:NSNull.null]
    onQueue:self.simulator.asyncQueue handleError:^(NSError *error) {
      return [[FBSimulatorError
        describeFormat:@"App %@ can't be launched as it isn't installed: %@", bundleID, error]
        failFuture];
    }];
}

- (FBFuture<NSNumber *> *)confirmApplicationLaunchState:(NSString *)bundleID launchMode:(FBApplicationLaunchMode)launchMode
{
  FBSimulator *simulator = self.simulator;
  return [[simulator
    runningApplicationWithBundleID:bundleID]
    onQueue:simulator.asyncQueue chain:^FBFuture<NSNull *> *(FBFuture<FBProcessInfo *> *processFuture) {
      FBProcessInfo *process = processFuture.result;
      if (!process) {
        return FBFuture.empty;
      }
      if (launchMode == FBApplicationLaunchModeFailIfRunning) {
        return [[FBSimulatorError
          describeFormat:@"App %@ can't be launched as is running (%@)", bundleID, process.shortDescription]
          failFuture];
      } else if (launchMode == FBApplicationLaunchModeRelaunchIfRunning) {
        return [[FBSimulatorSubprocessTerminationStrategy
          strategyWithSimulator:simulator]
          terminateApplication:bundleID];
      }
      return FBFuture.empty;
  }];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr
{
  // Start reading now, but don't block on the resolution, we will ensure that the read has started after the app has launched.
  FBFuture *readingFutures = [FBFuture futureWithFutures:@[
    [stdOut startReading],
    [stdErr startReading],
  ]];

  return [[self
    launchApplication:appLaunch stdOutPath:stdOut.filePath stdErrPath:stdErr.filePath]
    onQueue:self.simulator.workQueue fmap:^(NSNumber *result) {
      return [readingFutures mapReplace:result];
    }];
}

- (FBFuture<NSNumber *> *)isApplicationRunning:(NSString *)bundleID
{
  return [[self.simulator
    runningApplicationWithBundleID:bundleID]
    onQueue:self.simulator.workQueue chain:^(FBFuture<FBProcessInfo *> *future){
      FBProcessInfo *process = future.result;
      return process ? [FBFuture futureWithResult:@YES] : [FBFuture futureWithResult:@NO];
    }];
}

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
