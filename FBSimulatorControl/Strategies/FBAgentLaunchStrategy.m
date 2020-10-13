/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAgentLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import "FBProcessLaunchConfiguration+Simulator.h"
#import "FBAgentLaunchConfiguration+Simulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

typedef void (^FBAgentTerminationHandler)(int stat_loc);

@interface FBAgentLaunchStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

@end

@implementation FBAgentLaunchStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
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
  _processFetcher = simulator.processFetcher;

  return self;
}

#pragma mark Long-Running Processes

- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch
{
  FBSimulator *simulator = self.simulator;
  return [[agentLaunch.output
    createIOForTarget:simulator]
    onQueue:simulator.workQueue fmap:^(FBProcessIO *io) {
      return [self launchAgent:agentLaunch io:io];
    }];
}

- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch io:(FBProcessIO *)io
{
  FBSimulator *simulator = self.simulator;

  return [[io
    attach]
    onQueue:simulator.workQueue fmap:^(FBProcessIOAttachment *attachment) {
      // Launch the Process
      FBMutableFuture<NSNumber *> *processStatusFuture = [FBMutableFuture futureWithNameFormat:@"Process completion of %@ on %@", agentLaunch.agentBinary.path, simulator.udid];
      FBFuture<NSNumber *> *launchFuture = [FBAgentLaunchStrategy
        launchAgentWithSimulator:simulator
        launchPath:agentLaunch.agentBinary.path
        arguments:agentLaunch.arguments
        environment:agentLaunch.environment
        waitForDebugger:NO
        stdOut:attachment.stdOut
        stdErr:attachment.stdErr
        mode:agentLaunch.mode
        processStatusFuture:processStatusFuture];

      // Wrap in the container object
      return [[FBSimulatorAgentOperation
        operationWithSimulator:simulator
        configuration:agentLaunch
        stdOut:io.stdOut
        stdErr:io.stdErr
        launchFuture:launchFuture
        processStatusFuture:processStatusFuture]
        onQueue:self.simulator.workQueue notifyOfCompletion:^(FBFuture<FBSimulatorAgentOperation *> *future) {
          FBSimulatorAgentOperation *operation = future.result;
          if (!operation) {
            return;
          }
          [simulator.eventSink agentDidLaunch:operation];
        }];
    }];
}

#pragma mark Short-Running Processes

- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBAgentLaunchConfiguration *)agentLaunch
{
  return [self launchAndNotifyOfCompletion:agentLaunch consumer:[FBNullDataConsumer new]];
}

- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBAgentLaunchConfiguration *)agentLaunch consumer:(id<FBDataConsumer>)consumer
{
  FBProcessIO *io = [[FBProcessIO alloc] initWithStdIn:nil stdOut:[FBProcessOutput outputForDataConsumer:consumer] stdErr:FBProcessOutput.outputForNullDevice];
  return [[self
    launchAgent:agentLaunch io:io]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorAgentOperation *operation) {
      return [operation exitCode];
    }];
}

- (FBFuture<NSString *> *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  return [[self
    launchAndNotifyOfCompletion:agentLaunch consumer:consumer]
    onQueue:self.simulator.workQueue map:^(NSNumber *_) {
      return [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
    }];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)launchAgentWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable FBProcessStreamAttachment *)stdOut stdErr:(nullable FBProcessStreamAttachment *)stdErr mode:(FBAgentLaunchMode)mode processStatusFuture:(FBMutableFuture<NSNumber *> *)processStatusFuture
{
  // Get the Options
  NSDictionary<NSString *, id> *options = [FBAgentLaunchStrategy
    simDeviceLaunchOptionsWithSimulator:simulator
    launchPath:launchPath
    arguments:arguments
    environment:environment
    waitForDebugger:waitForDebugger
    stdOut:stdOut
    stdErr:stdErr
    mode:mode];

  // The Process launches and terminates synchronously
  FBMutableFuture<NSNumber *> *launchFuture = [FBMutableFuture futureWithNameFormat:@"Launch of %@ on %@", launchPath, simulator.udid];
  [simulator.device
    spawnAsyncWithPath:launchPath
    options:options
    terminationQueue:simulator.workQueue
    terminationHandler:^(int stat_loc) {
      // Notify that we're done with the process
      [processStatusFuture resolveWithResult:@(stat_loc)];
      // Close any open file handles that we have.
      // This is important because otherwise any reader will stall forever.
      // The SimDevice APIs do not automatically close any file descriptor passed into them, so we need to do this on it's behalf.
      // This would not be an issue if using simctl directly, as the stdout/stderr of the simctl process would close when the simctl process terminates.
      // However, using the simctl approach, we don't get the pid of the spawned process, this is merely logged internally.
      // Failing to close this end of the file descriptor would lead to the write-end of any pipe to not be closed and therefore it would leak.
      close(stdOut.fileDescriptor);
      close(stdErr.fileDescriptor);
    }
    completionQueue:simulator.workQueue
    completionHandler:^(NSError *innerError, pid_t processIdentifier){
      if (innerError) {
        [launchFuture resolveWithError:innerError];
      } else {
        [launchFuture resolveWithResult:@(processIdentifier)];
      }
  }];
  return launchFuture;
}

+ (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable FBProcessStreamAttachment *)stdOut stdErr:(nullable FBProcessStreamAttachment *)stdErr mode:(FBAgentLaunchMode)mode
{
  // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
  arguments = [@[launchPath] arrayByAddingObjectsFromArray:arguments];
  NSMutableDictionary<NSString *, id> *options = [FBProcessLaunchConfiguration launchOptionsWithArguments:arguments environment:environment waitForDebugger:waitForDebugger];
  if (stdOut){
    options[@"stdout"] = @(stdOut.fileDescriptor);
  }
  if (stdErr) {
    options[@"stderr"] = @(stdErr.fileDescriptor);
  }
  options[@"standalone"] = @([self shouldLaunchStandaloneOnSimulator:simulator mode:mode]);
  return [options copy];
}

+ (BOOL)shouldLaunchStandaloneOnSimulator:(FBSimulator *)simulator mode:(FBAgentLaunchMode)mode
{
  // Standalone means "launch directly, not via launchd"
  switch (mode) {
    case FBAgentLaunchModeLaunchd:
      return NO;
    case FBAgentLaunchModePosixSpawn:
      return YES;
    default:
      // Default behaviour is to use launchd if booted, otherwise use standalone.
      return simulator.state != FBiOSTargetStateBooted;
  }
}

@end
