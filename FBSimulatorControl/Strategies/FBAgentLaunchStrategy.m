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
#import "FBProcessOutput.h"
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
    onQueue:simulator.workQueue fmap:^(NSArray<id> *result) {
      FBProcessOutput *stdOut = result[0];
      stdOut = [stdOut isKindOfClass:FBProcessOutput.class] ? stdOut : nil;
      FBProcessOutput *stdErr = result[1];
      stdErr = [stdErr isKindOfClass:FBProcessOutput.class] ? stdErr : nil;
      return [self launchAgent:agentLaunch stdOut:stdOut stdErr:stdErr];
    }];
}

- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch stdOut:(FBProcessOutput *)stdOut stdErr:(FBProcessOutput *)stdErr
{
  FBSimulator *simulator = self.simulator;

  // Launch the Process
  FBMutableFuture *terminationFuture = [FBMutableFuture future];
  FBFuture<NSNumber *> *launchFuture = [self
    launchAgentWithLaunchPath:agentLaunch.agentBinary.path
    arguments:agentLaunch.arguments
    environment:agentLaunch.environment
    waitForDebugger:NO
    stdOut:stdOut.fileHandle
    stdErr:stdErr.fileHandle
    terminationFuture:terminationFuture];

  // Wrap in the container object
  return [[FBSimulatorAgentOperation
    operationWithSimulator:simulator
    configuration:agentLaunch
    stdOut:stdOut
    stdErr:stdErr
    launchFuture:launchFuture
    terminationFuture:terminationFuture]
    onQueue:self.simulator.workQueue notifyOfCompletion:^(FBFuture<FBSimulatorAgentOperation *> *future) {
      FBSimulatorAgentOperation *operation = future.result;
      if (!operation) {
        return;
      }
      [simulator.eventSink agentDidLaunch:operation];
    }];
}

#pragma mark Short-Running Processes

- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBAgentLaunchConfiguration *)agentLaunch
{
  return [self launchAndNotifyOfCompletion:agentLaunch consumer:[FBNullFileConsumer new]];
}

- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBAgentLaunchConfiguration *)agentLaunch consumer:(id<FBFileConsumer>)consumer
{
  // Start reading the pipe
  FBPipeReader *pipe = [FBPipeReader pipeReaderWithConsumer:consumer];
  return [[pipe
    startReading]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      // The Process launches and terminates synchronously
      FBMutableFuture<NSNumber *> *terminationFuture = [FBMutableFuture future];
      FBFuture<NSNumber *> *launchFuture = [self
        launchAgentWithLaunchPath:agentLaunch.agentBinary.path
        arguments:agentLaunch.arguments
        environment:agentLaunch.environment
        waitForDebugger:NO
        stdOut:pipe.pipe.fileHandleForWriting
        stdErr:nil
        terminationFuture:terminationFuture];

      return [[launchFuture
        onQueue:self.simulator.workQueue chain:^FBFuture *(FBFuture *future) {
          NSError *innerError = future.error;
          if (innerError) {
            return [FBFuture futureWithError:innerError];
          }
          return terminationFuture;
        }]
        onQueue:self.simulator.workQueue chain:^FBFuture<NSNumber *> *(FBFuture<NSNumber *> *innerFuture) {
          return [[pipe
            stopReading]
            rephraseFailure:@"Could not stop reading stdout of %@", agentLaunch];
        }];
    }];
}

- (FBFuture<NSString *> *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch
{
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
  return [[self
    launchAndNotifyOfCompletion:agentLaunch consumer:consumer]
    onQueue:self.simulator.workQueue map:^(NSNumber *_) {
      return [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
    }];
}

#pragma mark Private

- (FBFuture<NSNumber *> *)launchAgentWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable NSFileHandle *)stdOut stdErr:(nullable NSFileHandle *)stdErr terminationFuture:(nullable FBMutableFuture<NSNumber *> *)terminationFuture
{
  // Get the Options
  NSDictionary<NSString *, id> *options = [FBAgentLaunchConfiguration
    simDeviceLaunchOptionsWithLaunchPath:launchPath
    arguments:arguments
    environment:environment
    waitForDebugger:waitForDebugger
    stdOut:stdOut
    stdErr:stdErr];

  // The Process launches and terminates synchronously
  FBMutableFuture<NSNumber *> *launchFuture = [FBMutableFuture future];
  [self.simulator.device
    spawnAsyncWithPath:launchPath
    options:options
    terminationQueue:self.simulator.workQueue
    terminationHandler:^(int stat_loc) {
      [terminationFuture resolveWithResult:@(stat_loc)];
    }
    completionQueue:self.simulator.workQueue
    completionHandler:^(NSError *innerError, pid_t processIdentifier){
      if (innerError) {
        [launchFuture resolveWithError:innerError];
      } else {
        [launchFuture resolveWithResult:@(processIdentifier)];
      }
  }];
  return launchFuture;
}

@end
