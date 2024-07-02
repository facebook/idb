/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessTerminationStrategy.h"

#import "FBProcessFetcher.h"
#import "FBProcessInfo.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBControlCoreError (FBProcessTerminationStrategy)

- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher
{
  return [self
    extraInfo:[NSString stringWithFormat:@"%d_process", processIdentifier]
    value:[processFetcher processInfoFor:processIdentifier] ?: @"No Process Info"];
}

@end

static NSTimeInterval ProcessTableRemovalTimeout = 20.0;

static const FBProcessTerminationStrategyConfiguration FBProcessTerminationStrategyConfigurationDefault = {
  .signo = SIGKILL,
  .options =
    FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal |
    FBProcessTerminationStrategyOptionsCheckDeathAfterSignal |
    FBProcessTerminationStrategyOptionsBackoffToSIGKILL,
};

@interface FBProcessTerminationStrategy ()

@property (nonatomic, assign, readonly) FBProcessTerminationStrategyConfiguration configuration;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBProcessTerminationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithConfiguration:(FBProcessTerminationStrategyConfiguration)configuration processFetcher:(FBProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;
{
  return [[FBProcessTerminationStrategy alloc] initWithConfiguration:configuration processFetcher:processFetcher workQueue:workQueue logger:logger];
}

+ (instancetype)strategyWithProcessFetcher:(FBProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  return [self strategyWithConfiguration:FBProcessTerminationStrategyConfigurationDefault processFetcher:processFetcher workQueue:workQueue logger:logger];
}

- (instancetype)initWithConfiguration:(FBProcessTerminationStrategyConfiguration)configuration processFetcher:(FBProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(processFetcher);
  NSAssert(configuration.signo > 0 && configuration.signo < 32, @"Signal must be greater than 0 (SIGHUP) and less than 32 (SIGUSR2) was %d", configuration.signo);

  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _processFetcher = processFetcher;
  _workQueue = workQueue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)killProcessIdentifier:(pid_t)processIdentifier
{
  BOOL checkExists = (self.configuration.options & FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal) == FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal;
  if (checkExists && [self.processFetcher processInfoFor:processIdentifier] == nil) {
    return [[FBControlCoreError
      describeFormat:@"Could not find that process %d exists", processIdentifier]
      failFuture];
  }

  // Kill the process with kill(2).
  [self.logger.debug logFormat:@"Killing %d", processIdentifier];
  if (kill(processIdentifier, self.configuration.signo) != 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to kill %d: '%s'", processIdentifier, strerror(errno)]
      failFuture];
  }

  BOOL checkDeath = (self.configuration.options & FBProcessTerminationStrategyOptionsCheckDeathAfterSignal) == FBProcessTerminationStrategyOptionsCheckDeathAfterSignal;
  if (!checkDeath) {
    [self.logger.debug logFormat:@"Killed %d", processIdentifier];
    return FBFuture.empty;
  }

  // It may take some time for the process to have truly died, so wait for it to be so.
  // If this is a SIGKILL and it's taken a while for the process to dissapear, perhaps the process isn't
  // well behaved when responding to other terminating signals.
  // There's nothing more than can be done with a SIGKILL.
  [self.logger.debug logFormat:@"Waiting on %d to dissappear from the process table", processIdentifier];
  return [[[self
    onQueue:self.workQueue waitForProcessIdentifierToDie:processIdentifier processFetcher:self.processFetcher]
    timeout:ProcessTableRemovalTimeout waitingFor:@"Process %d to be removed from the process table", processIdentifier]
    onQueue:self.workQueue chain:^FBFuture *(FBFuture *future) {
      if (future.result) {
        [self.logger.debug logFormat:@"Process %d terminated", processIdentifier];
        return FBFuture.empty;
      }
      BOOL backoff = (self.configuration.options & FBProcessTerminationStrategyOptionsBackoffToSIGKILL) == FBProcessTerminationStrategyOptionsBackoffToSIGKILL;
      if (self.configuration.signo == SIGKILL || !backoff) {
        return [[[FBControlCoreError
          describeFormat:@"Timed out waiting for %d to dissapear from the process table", processIdentifier]
          attachProcessInfoForIdentifier:processIdentifier processFetcher:self.processFetcher]
          failFuture];
      }

      // Try with SIGKILL instead.
      FBProcessTerminationStrategyConfiguration configuration = self.configuration;
      configuration.signo = SIGKILL;
      [self.logger.debug logFormat:@"Backing off kill of %d to SIGKILL", processIdentifier];
      return [[[self
        strategyWithConfiguration:configuration]
        killProcessIdentifier:processIdentifier]
        rephraseFailure:@"Attempted to SIGKILL %d after failed kill with signo %d", processIdentifier, self.configuration.signo];
    }];
}

#pragma mark Private

- (FBProcessTerminationStrategy *)strategyWithConfiguration:(FBProcessTerminationStrategyConfiguration)configuration
{
  return [FBProcessTerminationStrategy strategyWithConfiguration:configuration processFetcher:self.processFetcher workQueue:self.workQueue logger:self.logger];
}

- (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForProcessIdentifierToDie:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher
{
  return [FBFuture onQueue:queue resolveWhen:^ BOOL {
    FBProcessInfo *polledProcess = [processFetcher processInfoFor:processIdentifier];
    return polledProcess == nil;
  }];
}

@end
