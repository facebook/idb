/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLaunchedProcess.h"

#import "FBControlCoreError.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreLogger.h"
#import "FBProcessIO.h"
#import "FBProcessSpawnCommands.h"
#import "FBProcessSpawnConfiguration.h"

@interface FBLaunchedProcess ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBLaunchedProcess

@synthesize configuration = _configuration;
@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;
@synthesize signal = _signal;
@synthesize statLoc = _statLoc;

#pragma mark Initializers

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal configuration:(FBProcessSpawnConfiguration *)configuration queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _processIdentifier = processIdentifier;
  _exitCode = exitCode;
  _signal = signal;
  _statLoc = statLoc;
  _queue = queue;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)acceptableExitCodes
{
  return [self.exitCode
    onQueue:self.queue fmap:^(NSNumber *exitCode) {
      return [[FBLaunchedProcess confirmExitCode:exitCode.intValue isAcceptable:acceptableExitCodes] mapReplace:exitCode];
    }];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [[FBFuture
    onQueue:self.queue resolve:^{
      // Do not kill if the process is already dead.
      if (self.statLoc.hasCompleted) {
        return self.statLoc;
      }
      kill(self.processIdentifier, signo);
      return self.statLoc;
    }]
    mapReplace:@(signo)];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [[[self
    sendSignal:signo]
    onQueue:self.queue timeout:timeout handler:^{
      [logger logFormat:@"Process %d didn't exit after wait for %f seconds for sending signal %d, sending SIGKILL now.", self.processIdentifier, timeout, signo];
      return [self sendSignal:SIGKILL];
    }]
    mapReplace:@(signo)];
}

#pragma mark Properties

- (nullable id)stdIn
{
  return [self.configuration.io.stdIn contents];
}

- (nullable id)stdOut
{
  return [self.configuration.io.stdOut contents];
}

- (nullable id)stdErr
{
  return [self.configuration.io.stdErr contents];
}

#pragma mark Private

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

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Process %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.statLoc];
}

@end
