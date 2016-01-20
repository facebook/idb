/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessTerminationStrategy.h"

#import <AppKit/AppKit.h>

#import "FBProcessInfo.h"
#import "FBProcessQuery+Helpers.h"
#import "FBProcessQuery.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLogger.h"

@interface FBProcessTerminationStrategy ()

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
@property (nonatomic, assign, readonly) int signo;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;

@end

@interface FBApplicationTerminationStrategy_WorkspaceQuit : FBProcessTerminationStrategy

@end

@implementation FBApplicationTerminationStrategy_WorkspaceQuit

- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error
{
  // Obtain the NSRunningApplication for the given Application.
  NSRunningApplication *application = [self.processQuery runningApplicationForProcess:process];
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
    attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
    logger:self.logger]
    failBool:error];
}

@end

@implementation FBProcessTerminationStrategy

+ (instancetype)withProcessKilling:(FBProcessQuery *)processQuery signo:(int)signo logger:(id<FBSimulatorLogger>)logger;
{
  return [[self alloc] initWithProcessQuery:processQuery signo:signo logger:logger];
}

+ (instancetype)withRunningApplicationTermination:(FBProcessQuery *)processQuery signo:(int)signo logger:(id<FBSimulatorLogger>)logger;
{
  return [[FBApplicationTerminationStrategy_WorkspaceQuit alloc] initWithProcessQuery:processQuery signo:signo logger:logger];
}

- (instancetype)initWithProcessQuery:(FBProcessQuery *)processQuery signo:(int)signo logger:(id<FBSimulatorLogger>)logger
{
  NSParameterAssert(processQuery);
  NSAssert(signo > 0 && signo < 32, @"Signal must be greater than 0 (SIGHUP) and less than 32 (SIGUSR2) was %d", signo);

  self = [super init];
  if (!self) {
    return nil;
  }

  _processQuery = processQuery;
  _signo = signo;
  _logger = logger;

  return self;
}

- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error
{
  FBProcessInfo *actualProcess = [self.processQuery processInfoFor:process.processIdentifier];
  if (![actualProcess isEqual:process]) {
    return [[[FBSimulatorError
      describeFormat:@"Avoiding killing %@ as it differs from the actual process %@", process.shortDescription, actualProcess.shortDescription]
      logger:self.logger]
      failBool:error];
  }

  // Kill the process with kill(2).
  [self.logger.debug logFormat:@"Killing %@", process.shortDescription];
  if (kill(process.processIdentifier, self.signo) != 0) {
    // If the kill failed, then extract the error information and return.
    int errorCode = errno;
    if (errorCode == EPERM) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the sending process does not have the privelages", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
        logger:self.logger]
        failBool:error];
    }
    if (errorCode == ESRCH) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the sending process does not exist", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
        logger:self.logger]
        failBool:error];
    }
    if (errorCode == EINVAL) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to kill process %@ as the signal %d was not a valid signal number", process.shortDescription, self.signo]
        attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
        logger:self.logger]
        failBool:error];
    }
    return [[FBSimulatorError
      describeFormat:@"Failed to kill process %@ with unknown errno %d", process.shortDescription, errorCode]
      failBool:error];
  }

  // It may take some time for the process to have truly died, so wait for it to be so.
  [self.logger.debug logFormat:@"Waiting on %@ to dissappear from the process table", process.shortDescription];
  if (![self.processQuery waitForProcessToDie:process timeout:FBSimulatorControlGlobalConfiguration.fastTimeout]) {
    // If this is a SIGKILL and it's taken a while for the process to dissapear, perhaps the process isn't
    // well behaved when responding to other terminating signals.
    // There's nothing more than can be done with a SIGKILL.
    if (self.signo == SIGKILL) {
      return [[[[FBSimulatorError
        describeFormat:@"Timed out waiting for %@ to dissapear from the process table", process.shortDescription]
        attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
        logger:self.logger]
        failBool:error];
    }

    // Try with SIGKILL instead.
    NSError *innerError = nil;
    if (![[FBProcessTerminationStrategy withProcessKilling:self.processQuery signo:SIGKILL logger:self.logger] killProcess:process error:&innerError]) {
      return [[[[[FBSimulatorError
        describeFormat:@"Attempted to SIGKILL %@ after failed kill with signo %d", process.shortDescription, self.signo]
        attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
        logger:self.logger]
        causedBy:innerError]
        failBool:error];
    }
    // If we get here, then the process was killed.
  }

  [self.logger.debug logFormat:@"Killed %@", process.shortDescription];
  return YES;
}

- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error
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
