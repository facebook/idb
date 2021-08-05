/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessSpawnCommands.h"

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
  FBFuture<NSNumber *> *signal = [self sendSignal:signo toProcess:process];
  FBFuture<NSNumber *> *kill = [[[FBFuture
    futureWithResult:NSNull.null]
    delay:timeout]
    onQueue:queue fmap:^(id _) {
      [logger logFormat:@"Process %d didn't exit after wait for %f seconds for sending signal %d, sending SIGKILL now.", process.processIdentifier, timeout, signo];
      return [self sendSignal:SIGKILL toProcess:process];
    }];
  return [[FBFuture race:@[signal, kill]] mapReplace:@(signo)];
}

@end
