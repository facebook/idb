/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLaunchedProcess.h"

#import "FBProcessSpawnCommands.h"
#import "FBProcessSpawnConfiguration.h"

@implementation FBLaunchedProcess

@synthesize configuration = _configuration;
@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;
@synthesize signal = _signal;
@synthesize statLoc = _statLoc;

#pragma mark Initializers

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal configuration:(FBProcessSpawnConfiguration *)configuration
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

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)exitCodes
{
  return [FBProcessSpawnCommandHelpers exitedWithCode:self.exitCode isAcceptable:exitCodes];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo toProcess:self];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo backingOffToKillWithTimeout:timeout toProcess:self logger:logger];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Process %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.statLoc];
}

@end
