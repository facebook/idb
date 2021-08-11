/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessSpawnCommands.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataBuffer.h"
#import "FBLaunchedProcess.h"
#import "FBProcessIO.h"
#import "FBProcessSpawnConfiguration.h"

@implementation FBProcessSpawnCommandHelpers

+ (dispatch_queue_t)queue
{
  return dispatch_queue_create("com.facebook.fbcontrolcore.process_spawn_helpers", DISPATCH_QUEUE_CONCURRENT);
}

+ (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBProcessSpawnConfiguration *)configuration withCommands:(id<FBProcessSpawnCommands>)commands
{
  return [[commands
    launchProcess:configuration]
    onQueue:self.queue fmap:^(id<FBLaunchedProcess> process) {
      return [process exitCode];
    }];
}

+ (FBFuture<NSString *> *)launchConsumingStdout:(FBProcessSpawnConfiguration *)configuration withCommands:(id<FBProcessSpawnCommands>)commands
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  FBProcessIO *io = [[FBProcessIO alloc]
    initWithStdIn:configuration.io.stdIn
    stdOut:[FBProcessOutput outputForDataConsumer:consumer]
    stdErr:configuration.io.stdOut];
  FBProcessSpawnConfiguration *derived = [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:configuration.launchPath
    arguments:configuration.arguments
    environment:configuration.environment
    io:io
    mode:configuration.mode];
  return [[self
    launchAndNotifyOfCompletion:derived withCommands:commands]
    onQueue:self.queue map:^(NSNumber *_) {
      return [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
    }];
}

+ (FBFuture<NSNumber *> *)sendSignal:(int)signo toProcess:(id<FBLaunchedProcess>)process
{
  return [[FBFuture
    onQueue:self.queue resolve:^{
      // Do not kill if the process is already dead.
      if (process.statLoc.hasCompleted) {
        return process.statLoc;
      }
      kill(process.processIdentifier, signo);
      return process.statLoc;
    }]
    mapReplace:@(signo)];
}

+ (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout toProcess:(id<FBLaunchedProcess>)process logger:(nullable id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task_terminate", DISPATCH_QUEUE_SERIAL);
  return [[[self
    sendSignal:signo toProcess:process]
    onQueue:queue timeout:timeout handler:^{
      [logger logFormat:@"Process %d didn't exit after wait for %f seconds for sending signal %d, sending SIGKILL now.", process.processIdentifier, timeout, signo];
      return [self sendSignal:SIGKILL toProcess:process];
    }]
    mapReplace:@(signo)];
}

+ (void)resolveProcessFinishedWithStatLoc:(int)statLoc inTeardownOfIOAttachment:(FBProcessIOAttachment *)attachment statLocFuture:(FBMutableFuture<NSNumber *> *)statLocFuture exitCodeFuture:(FBMutableFuture<NSNumber *> *)exitCodeFuture signalFuture:(FBMutableFuture<NSNumber *> *)signalFuture processIdentifier:(pid_t)processIdentifier configuration:(FBProcessSpawnConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Process %d (%@) has exited, tearing down IO...", processIdentifier, configuration.processName];
  [[attachment
    detach]
    onQueue:queue notifyOfCompletion:^(id _) {
      [logger logFormat:@"Teardown of IO for process %d (%@) has completed", processIdentifier, configuration.processName];
      [statLocFuture resolveWithResult:@(statLoc)];
      if (WIFSIGNALED(statLoc)) {
        int signalCode = WTERMSIG(statLoc);
        NSString *message = [NSString stringWithFormat:@"Process %d (%@) died with signal %d", processIdentifier, configuration.processName, signalCode];
        [logger log:message];
        NSError *error = [[FBControlCoreError describe:message] build];
        [exitCodeFuture resolveWithError:error];
        [signalFuture resolveWithResult:@(signalCode)];
      } else {
        int exitCode = WEXITSTATUS(statLoc);
        NSString *message = [NSString stringWithFormat:@"Process %d (%@) died with exit code %d", processIdentifier, configuration.processName, exitCode];
        [logger log:message];
        NSError *error = [[FBControlCoreError describe:message] build];
        [signalFuture resolveWithError:error];
        [exitCodeFuture resolveWithResult:@(exitCode)];
      }
    }];
}

+ (FBFuture<NSNull *> *)confirmExitCode:(int)exitCode isAcceptable:(NSSet<NSNumber *> *)acceptableExitCodes
{
  // If exit codes are defined, check them.
  if (acceptableExitCodes == nil) {
    return FBFuture.empty;
  }
  if ([acceptableExitCodes containsObject:@(exitCode)]) {
    return FBFuture.empty;
  }
  return [[FBControlCoreError
    describeFormat:@"Exit Code %d is not acceptable %@", exitCode, [FBCollectionInformation oneLineDescriptionFromArray:acceptableExitCodes.allObjects]]
    failFuture];
}

+ (FBFuture<NSNull *> *)exitedWithCode:(FBFuture<NSNumber *> *)exitCodeFuture isAcceptable:(NSSet<NSNumber *> *)acceptableExitCodes
{
  return [exitCodeFuture
    onQueue:self.queue fmap:^(NSNumber *exitCode) {
      return [[self confirmExitCode:exitCode.intValue isAcceptable:acceptableExitCodes] mapReplace:exitCode];
    }];
}

@end
