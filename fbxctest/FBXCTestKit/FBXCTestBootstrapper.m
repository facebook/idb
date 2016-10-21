/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestBootstrapper.h"

#import "FBJSONTestReporter.h"
#import "FBXCTestConfiguration.h"
#import "FBXCTestRunner.h"
#import "FBXCTestLogger.h"

@interface FBXCTestBootstrapper ()

@property (nonatomic, strong, readonly) FBXCTestLogger *logger;

@end

@implementation FBXCTestBootstrapper

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = FBXCTestLogger.defaultLoggerInDefaultDirectory;
  [FBControlCoreGlobalConfiguration setDefaultLogger:_logger];

  return self;
}

- (BOOL)bootstrap
{
  NSError *error;
  NSString *workingDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];

  if (![NSFileManager.defaultManager createDirectoryAtPath:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [self printErrorMessage:error];
  }

  FBXCTestConfiguration *configuration = [[FBXCTestConfiguration alloc] initWithReporter:nil logger:self.logger processUnderTestEnvironment:@{}];
  if (![configuration loadWithArguments:NSProcessInfo.processInfo.arguments workingDirectory:workingDirectory error:&error]) {
    return [self printErrorMessage:error];
  }

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  if (![testRunner executeTestsWithError:&error]) {
    return [self printErrorMessage:error];
  }

  if (![NSFileManager.defaultManager removeItemAtPath:workingDirectory error:&error]) {
    return [self printErrorMessage:error];
  }

  return YES;
}


- (BOOL)printErrorMessage:(NSError *)error
{
  fputs(error.description.UTF8String, stderr);

  NSString *lastLines = [self.logger allLinesOfOutput];
  if (lastLines) {
    fputs(lastLines.UTF8String, stderr);
  }

  fflush(stderr);
  return NO;
}

@end
