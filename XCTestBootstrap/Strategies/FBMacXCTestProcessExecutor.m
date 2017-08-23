/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBMacXCTestProcessExecutor.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestShimConfiguration.h"
#import "FBLogicTestProcess.h"

@interface FBMacXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;
@property (nonatomic, strong, readwrite, nullable) FBTask *task;

@end

@implementation FBMacXCTestProcessExecutor

+ (instancetype)executorWithConfiguration:(FBXCTestConfiguration *)configuration
{
  return [[self alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;

  return self;
}

- (pid_t)logicTestProcess:(FBLogicTestProcess *)process startWithError:(NSError **)error
{
  self.task = [[[[[[[[FBTaskBuilder
    withLaunchPath:process.launchPath]
    withArguments:process.arguments]
    withEnvironment:process.environment]
    withStdOutConsumer:process.stdOutReader]
    withStdErrConsumer:process.stdErrReader]
    withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
    build]
    startAsynchronously];

  if (self.task.error) {
    [[[FBControlCoreError
      describeFormat:@"Logic Test Process Errored %@", self.task.error.localizedDescription]
      causedBy:self.task.error]
      fail:error];
    self.task = nil;
    return -1;
  }
  return self.task.processIdentifier;
}

- (void)terminateLogicTestProcess:(FBLogicTestProcess *)process;
{
  [self.task terminate];
}

- (BOOL)logicTestProcess:(FBLogicTestProcess *)process waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (!self.task) {
    return [[FBControlCoreError
      describe:@"No task to await completion of"]
      failBool:error];
  }

  // Perform the underlying wait.
  FBTask *task = self.task;
  NSError *timeoutError = nil;
  BOOL waitSuccessful = [task waitForCompletionWithTimeout:timeout error:&timeoutError];
  int exitCode = task.error.userInfo[@"exitcode"] ? [task.error.userInfo[@"exitcode"] intValue] : 0;

  // Check that we exited normally
  if (![process processDidTerminateNormallyWithProcessIdentifier:task.processIdentifier didTimeout:(waitSuccessful == NO) exitCode:exitCode error:error]) {
    return NO;
  }
  return YES;
}

- (NSString *)shimPath
{
  return self.configuration.shims.macOSTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.configuration.shims.macOSQueryShimPath;
}

@end
