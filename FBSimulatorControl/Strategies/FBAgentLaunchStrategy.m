/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAgentLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import "FBProcessLaunchConfiguration+Simulator.h"
#import "FBAgentLaunchConfiguration+Simulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorDiagnostics.h"
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
  return [[agentLaunch
    createOutputForSimulator:simulator]
    onQueue:simulator.workQueue fmap:^(NSArray<FBProcessOutput *> *outputs) {
      FBProcessOutput *stdOut = outputs[0];
      FBProcessOutput *stdErr = outputs[1];
      return [self launchAgent:agentLaunch stdOut:stdOut stdErr:stdErr];
    }];
}

- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch stdOut:(FBProcessOutput *)stdOut stdErr:(FBProcessOutput *)stdErr
{
  FBSimulator *simulator = self.simulator;

  return [[FBFuture
    futureWithFutures:@[[stdOut attachToFileHandle], [stdErr attachToFileHandle]]]
    onQueue:simulator.workQueue fmap:^(NSArray<NSFileHandle *> *fileHandles) {
      // Extract the File Handles
      NSFileHandle *stdOutHandle = fileHandles[0];
      NSFileHandle *stdErrHandle = fileHandles[1];

      // Launch the Process
      FBMutableFuture<NSNumber *> *processStatusFuture = FBMutableFuture.future;
      FBFuture<NSNumber *> *launchFuture = [FBAgentLaunchStrategy
        launchAgentWithSimulator:simulator
        launchPath:agentLaunch.agentBinary.path
        arguments:agentLaunch.arguments
        environment:agentLaunch.environment
        waitForDebugger:NO
        stdOut:stdOutHandle
        stdErr:stdErrHandle
        processStatusFuture:processStatusFuture];

      // Wrap in the container object
      return [[FBSimulatorAgentOperation
        operationWithSimulator:simulator
        configuration:agentLaunch
        stdOut:stdOut
        stdErr:stdErr
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
  return [[self
    launchAgent:agentLaunch stdOut:[FBProcessOutput outputForDataConsumer:consumer] stdErr:FBProcessOutput.outputForNullDevice]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorAgentOperation *operation) {
      return [operation exitCode];
    }];
}

- (FBFuture<NSString *> *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch
{
  id<FBAccumulatingLineBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  return [[self
    launchAndNotifyOfCompletion:agentLaunch consumer:consumer]
    onQueue:self.simulator.workQueue map:^(NSNumber *_) {
      return [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
    }];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)launchAgentWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable NSFileHandle *)stdOut stdErr:(nullable NSFileHandle *)stdErr processStatusFuture:(FBMutableFuture<NSNumber *> *)processStatusFuture
{
  // Get the Options
  NSDictionary<NSString *, id> *options = [FBAgentLaunchStrategy
    simDeviceLaunchOptionsWithSimulator:simulator
    launchPath:launchPath
    arguments:arguments
    environment:environment
    waitForDebugger:waitForDebugger
    stdOut:stdOut
    stdErr:stdErr];

  // The Process launches and terminates synchronously
  FBMutableFuture<NSNumber *> *launchFuture = [FBMutableFuture future];
  [simulator.device
    spawnAsyncWithPath:launchPath
    options:options
    terminationQueue:simulator.workQueue
    terminationHandler:^(int stat_loc) {
      [processStatusFuture resolveWithResult:@(stat_loc)];
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

+ (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable NSFileHandle *)stdOut stdErr:(nullable NSFileHandle *)stdErr
{
  // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
  arguments = [@[launchPath] arrayByAddingObjectsFromArray:arguments];
  NSMutableDictionary<NSString *, id> *options = [FBProcessLaunchConfiguration launchOptionsWithArguments:arguments environment:environment waitForDebugger:waitForDebugger];
  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  if (simulator.state != FBiOSTargetStateBooted) {
    options[@"standalone"] = @YES;
  }
  return [options copy];
}

@end
