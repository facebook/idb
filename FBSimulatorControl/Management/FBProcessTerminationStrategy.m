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
#import "FBSimulatorError.h"
#import "FBSimulatorLogger.h"
#import "FBProcessQuery+Helpers.h"
#import "FBProcessQuery.h"

@interface FBProcessTerminationStrategy ()

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
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
    return [super killProcess:process error:error];
  }
  // Terminate and return if successful.
  if ([application terminate]) {
    return YES;
  }
  // If the App is already terminated, everything is ok.
  if (application.isTerminated) {
    return YES;
  }
  // I find your lack of termination disturbing.
  if ([application forceTerminate]) {
    return YES;
  }
  // If the App is already terminated, everything is ok.
  if (application.isTerminated) {
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

+ (instancetype)withProcessKilling:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger;
{
  return [[self alloc] initWithProcessQuery:processQuery logger:logger];
}

+ (instancetype)withRunningApplicationTermination:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger;
{
  return [[FBApplicationTerminationStrategy_WorkspaceQuit alloc] initWithProcessQuery:processQuery logger:logger];
}

- (instancetype)initWithProcessQuery:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger
{
  NSParameterAssert(processQuery);

  self = [super init];
  if (!self) {
    return nil;
  }

  _processQuery = processQuery;
  _logger = logger;

  return self;
}

- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error
{
  // The kill was successful, all is well.
  [self.logger.debug logFormat:@"Killing %@", process.shortDescription];
  if (kill(process.processIdentifier, SIGTERM) == 0) {
    return YES;
  }
  int errorCode = errno;
  if (errorCode == EPERM) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to kill process %@ as the sending process does not have the privelages", process]
      attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
      logger:self.logger]
      failBool:error];
  }
  if (errorCode == ESRCH) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to kill process %@ as the sending process does not exist", process]
      attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
      logger:self.logger]
      failBool:error];
  }
  if (errorCode == EINVAL) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to kill process %@ as the signal was not a valid signal number", process]
      attachProcessInfoForIdentifier:process.processIdentifier query:self.processQuery]
      logger:self.logger]
      failBool:error];
  }
  [self.logger.debug logFormat:@"Killed %@", process.shortDescription];
  return [[FBSimulatorError describeFormat:@"Failed to kill process %@ with unknown errno %d", process, errorCode] failBool:error];
}

@end
