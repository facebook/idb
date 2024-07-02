/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessSpawnCommands.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataBuffer.h"
#import "FBProcess.h"
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
    onQueue:self.queue fmap:^(FBProcess *process) {
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
        NSString *message = [NSString stringWithFormat:@"Process %d (%@) exited with signal %d", processIdentifier, configuration.processName, signalCode];
        [logger log:message];
        NSError *error = [[FBControlCoreError describe:message] build];
        [exitCodeFuture resolveWithError:error];
        [signalFuture resolveWithResult:@(signalCode)];
      } else {
        int exitCode = WEXITSTATUS(statLoc);
        NSString *message = [NSString stringWithFormat:@"Process %d (%@) exited with code %d", processIdentifier, configuration.processName, exitCode];
        [logger log:message];
        NSError *error = [[FBControlCoreError describe:message] build];
        [signalFuture resolveWithError:error];
        [exitCodeFuture resolveWithResult:@(exitCode)];
      }
    }];
}

@end
