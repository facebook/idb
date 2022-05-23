/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorProcessSpawnCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorProcessSpawnCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorProcessSpawnCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
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

#pragma mark FBSimulatorProcessSpawnCommands Implementation

- (FBFuture<FBProcess *> *)launchProcess:(FBProcessSpawnConfiguration *)configuration
{
  FBSimulator *simulator = self.simulator;

  return [[configuration.io
    attach]
    onQueue:simulator.workQueue fmap:^(FBProcessIOAttachment *attachment) {
      return [FBSimulatorProcessSpawnCommands
        launchProcessWithSimulator:simulator
        configuration:configuration
        attachment:attachment];
    }];
}

#pragma mark Public

+ (NSDictionary<NSString *, id> *)launchOptionsWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, id> *options = [NSMutableDictionary dictionary];
  options[@"arguments"] = arguments;
  options[@"environment"] = environment ? environment: @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"};
  if (waitForDebugger) {
    options[@"wait_for_debugger"] = @1;
  }
  return options;
}

#pragma mark Private

+ (FBFuture<FBProcess *> *)launchProcessWithSimulator:(FBSimulator *)simulator configuration:(FBProcessSpawnConfiguration *)configuration attachment:(FBProcessIOAttachment *)attachment
{
  // Prepare captured futures
  id<FBControlCoreLogger> logger = simulator.logger;
  FBMutableFuture<NSNumber *> *launchFuture = [FBMutableFuture futureWithNameFormat:@"Launch of %@ on %@", configuration.launchPath, simulator.udid];
  FBMutableFuture<NSNumber *> *statLoc = [FBMutableFuture futureWithNameFormat:@"Process completion of %@ on %@", configuration.launchPath, simulator.udid];
  FBMutableFuture<NSNumber *> *exitCode = [FBMutableFuture futureWithNameFormat:@"Process exit of %@ on %@", configuration.launchPath, simulator.udid];
  FBMutableFuture<NSNumber *> *signal = [FBMutableFuture futureWithNameFormat:@"Process signal of %@ on %@", configuration.launchPath, simulator.udid];

  // Get the Options
  NSDictionary<NSString *, id> *options = [self
    simDeviceLaunchOptionsWithSimulator:simulator
    launchPath:configuration.launchPath
    arguments:configuration.arguments
    environment:configuration.environment
    waitForDebugger:NO
    stdOut:attachment.stdOut
    stdErr:attachment.stdErr
    mode:configuration.mode];

  // The Process launches and terminates asynchronously.
  [simulator.device
    spawnAsyncWithPath:configuration.launchPath
    options:options
    terminationQueue:simulator.workQueue
    terminationHandler:^(int stat_loc) {
      // Notify that we're done with the process to each of the futures.
      [FBProcessSpawnCommandHelpers
        resolveProcessFinishedWithStatLoc:stat_loc
        inTeardownOfIOAttachment:attachment
        statLocFuture:statLoc
        exitCodeFuture:exitCode
        signalFuture:signal
        processIdentifier:[launchFuture.result intValue]
        configuration:configuration
        queue:simulator.workQueue
        logger:logger];

      // Close any open file handles that we have.
      // This is important because otherwise any reader will stall forever.
      // The SimDevice APIs do not automatically close any file descriptor passed into them, so we need to do this on it's behalf.
      // This would not be an issue if using simctl directly, as the stdout/stderr of the simctl process would close when the simctl process terminates.
      // However, using the simctl approach, we don't get the pid of the spawned process, this is merely logged internally.
      // Failing to close this end of the file descriptor would lead to the write-end of any pipe to not be closed and therefore it would leak.
      
      [attachment.stdOut close];
      [attachment.stdErr close];
    }
    completionQueue:simulator.workQueue
    completionHandler:^(NSError *innerError, pid_t processIdentifier){
      if (innerError) {
        [launchFuture resolveWithError:innerError];
      } else {
        [launchFuture resolveWithResult:@(processIdentifier)];
      }
  }];

  // Map to the FBProcess implementation.
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      // Wrap in the container object
      pid_t processIdentifier = processIdentifierNumber.intValue;
      return [[FBProcess alloc] initWithProcessIdentifier:processIdentifier statLoc:statLoc exitCode:exitCode signal:signal configuration:configuration queue:simulator.workQueue];
    }];
}

+ (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable FBProcessStreamAttachment *)stdOut stdErr:(nullable FBProcessStreamAttachment *)stdErr mode:(FBProcessSpawnMode)mode
{
  // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
  arguments = [@[launchPath] arrayByAddingObjectsFromArray:arguments];
  NSMutableDictionary<NSString *, id> *options = [[self launchOptionsWithArguments:arguments environment:environment waitForDebugger:waitForDebugger] mutableCopy];
  if (stdOut){
    options[@"stdout"] = @(stdOut.fileDescriptor);
  }
  if (stdErr) {
    options[@"stderr"] = @(stdErr.fileDescriptor);
  }
  options[@"standalone"] = @([self shouldLaunchStandaloneOnSimulator:simulator mode:mode]);
  return [options copy];
}

+ (BOOL)shouldLaunchStandaloneOnSimulator:(FBSimulator *)simulator mode:(FBProcessSpawnMode)mode
{
  // Standalone means "launch directly, not via launchd"
  switch (mode) {
    case FBProcessSpawnModeLaunchd:
      return NO;
    case FBProcessSpawnModePosixSpawn:
      return YES;
    default:
      // Default behaviour is to use launchd if booted, otherwise use standalone.
      return simulator.state != FBiOSTargetStateBooted;
  }
}

@end
