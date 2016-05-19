/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessTerminationStrategy.h"

#import <Cocoa/Cocoa.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"

static const FBProcessTerminationStrategyConfiguration FBProcessTerminationStrategyConfigurationDefault = {
  .signo = SIGKILL,
  .options =
    FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal |
    FBProcessTerminationStrategyOptionsCheckDeathAfterSignal |
    FBProcessTerminationStrategyOptionsBackoffToSIGKILL,
};

@interface FBProcessTerminationStrategy ()

@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, assign, readonly) FBProcessTerminationStrategyConfiguration configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBProcessTerminationStrategy_WorkspaceQuit : FBProcessTerminationStrategy

@end

@implementation FBProcessTerminationStrategy_WorkspaceQuit

- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error
{
  // Obtain the NSRunningApplication for the given Application.
  NSRunningApplication *application = [self.processFetcher runningApplicationForProcess:process];
  // If the Application Handle doesn't exist, assume it isn't an Application and use good-ole kill(2)
  if ([application isKindOfClass:NSNull.class]) {
    [self.logger.debug logFormat:@"Application Handle for %@ does not exist, falling back to kill(2)", process.shortDescription];
    return [super killProcess:process error:error];
  }
  // Terminate and return if successful.
  if ([application terminate]) {
    [self.logger.debug logFormat:@"Terminated %@ with Application Termination", process.shortDescription];
    return YES;
  }
  // If the App is already terminated, everything is ok.
  if (application.isTerminated) {
    [self.logger.debug logFormat:@"Application %@ is Terminated", process.shortDescription];
    return YES;
  }
  // I find your lack of termination disturbing.
  if ([application forceTerminate]) {
    [self.logger.debug logFormat:@"Terminated %@ with Forced Application Termination", process.shortDescription];
    return YES;
  }
  // If the App is already terminated, everything is ok.
  if (application.isTerminated) {
    [self.logger.debug logFormat:@"Application %@ terminated after Forced Application Termination", process.shortDescription];
    return YES;
  }
  return [[[[FBSimulatorError
    describeFormat:@"Could not terminate Application %@", application]
    attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
    logger:self.logger]
    failBool:error];
}

@end

@implementation FBProcessTerminationStrategy

+ (instancetype)withConfiguration:(FBProcessTerminationStrategyConfiguration)configuration processFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  BOOL useWorkspaceKilling = (configuration.options & FBProcessTerminationStrategyOptionsUseNSRunningApplication) == FBProcessTerminationStrategyOptionsUseNSRunningApplication;
  return useWorkspaceKilling
    ? [[FBProcessTerminationStrategy_WorkspaceQuit alloc] initWithConfiguration:configuration processFetcher:processFetcher logger:logger]
    : [[FBProcessTerminationStrategy alloc] initWithConfiguration:configuration processFetcher:processFetcher logger:logger];
}

+ (instancetype)withProcessFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  return [self withConfiguration:FBProcessTerminationStrategyConfigurationDefault processFetcher:processFetcher logger:logger];
}

- (instancetype)initWithConfiguration:(FBProcessTerminationStrategyConfiguration)configuration processFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(processFetcher);
  NSAssert(configuration.signo > 0 && configuration.signo < 32, @"Signal must be greater than 0 (SIGHUP) and less than 32 (SIGUSR2) was %d", configuration.signo);

  self = [super init];
  if (!self) {
    return nil;
  }

  _processFetcher = processFetcher;
  _configuration = configuration;
  _logger = logger;

  return self;
}

- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error
{
  BOOL checkExists = (self.configuration.options & FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal) == FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal;
  NSError *innerError = nil;
  if (checkExists && ![self.processFetcher processExists:process error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not find that process %@ exists", process]
      logger:self.logger]
      causedBy:innerError]
      failBool:error];
  }

  // Kill the process with kill(2).
  [self.logger.debug logFormat:@"Killing %@", process.shortDescription];
  if (kill(process.processIdentifier, self.configuration.signo) != 0) {
    // If the kill failed, then extract the error information and return.
    int errorCode = errno;
    if (errorCode == EPERM) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the sending process does not have the privelages", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
        logger:self.logger]
        failBool:error];
    }
    if (errorCode == ESRCH) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the sending process does not exist", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
        logger:self.logger]
        failBool:error];
    }
    if (errorCode == EINVAL) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the signal %d was not a valid signal number", process.shortDescription, self.configuration.signo]
        attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
        logger:self.logger]
        failBool:error];
    }
    return [[FBSimulatorError
      describeFormat:@"Failed to kill process %@ with unknown errno %d", process.shortDescription, errorCode]
      failBool:error];
  }

  BOOL checkDeath = (self.configuration.options & FBProcessTerminationStrategyOptionsCheckDeathAfterSignal) == FBProcessTerminationStrategyOptionsCheckDeathAfterSignal;
  if (!checkDeath) {
    [self.logger.debug logFormat:@"Killed %@", process.shortDescription];
    return YES;
  }

  // It may take some time for the process to have truly died, so wait for it to be so.
  [self.logger.debug logFormat:@"Waiting on %@ to dissappear from the process table", process.shortDescription];
  if (![self.processFetcher waitForProcessToDie:process timeout:FBControlCoreGlobalConfiguration.fastTimeout]) {
    // If this is a SIGKILL and it's taken a while for the process to dissapear, perhaps the process isn't
    // well behaved when responding to other terminating signals.
    // There's nothing more than can be done with a SIGKILL.
    BOOL backoff = (self.configuration.options & FBProcessTerminationStrategyOptionsBackoffToSIGKILL) == FBProcessTerminationStrategyOptionsBackoffToSIGKILL;
    if (self.configuration.signo == SIGKILL || !backoff) {
      return [[[[FBSimulatorError
        describeFormat:@"Timed out waiting for %@ to dissapear from the process table", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
        logger:self.logger]
        failBool:error];
    }

    // Try with SIGKILL instead.
    FBProcessTerminationStrategyConfiguration configuration = self.configuration;
    configuration.signo = SIGKILL;
    [self.logger.debug logFormat:@"Backing off kill of %@ to SIGKILL", process.shortDescription];
    if (![[FBProcessTerminationStrategy withConfiguration:configuration processFetcher:self.processFetcher logger:self.logger] killProcess:process error:&innerError]) {
      return [[[[[FBSimulatorError
        describeFormat:@"Attempted to SIGKILL %@ after failed kill with signo %d", process.shortDescription, self.configuration.signo]
        attachProcessInfoForIdentifier:process.processIdentifier processFetcher:self.processFetcher]
        logger:self.logger]
        causedBy:innerError]
        failBool:error];
    }
  }

  [self.logger.debug logFormat:@"Killed %@", process.shortDescription];
  return YES;
}

- (BOOL)killProcesses:(NSArray<FBProcessInfo *> *)processes error:(NSError **)error
{
  for (FBProcessInfo *process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (![self killProcess:process error:error]) {
      return NO;
    }
  }
  return YES;
}

@end
