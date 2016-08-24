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
#import "FBTestRunConfiguration.h"
#import "FBXCTestRunner.h"
#import "FBXCTestLogger.h"

@implementation FBXCTestBootstrapper

+ (BOOL)bootstrap
{
  NSError *error;
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *workingDirectory =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  if (![fileManager createDirectoryAtPath:workingDirectory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]) {
    return handleError(error, nil);
  }

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:nil processUnderTestEnvironment:@{}];
  if (![configuration loadWithArguments:[NSProcessInfo processInfo].arguments
                       workingDirectory:workingDirectory
                                  error:&error]) {
    return handleError(error, configuration.logger);
  }

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  if (![testRunner executeTestsWithError:&error]) {
    return handleError(error, configuration.logger);
  }

  if (![fileManager removeItemAtPath:workingDirectory error:&error]) {
    return handleError(error, configuration.logger);
  }

  return YES;
}

static inline BOOL handleError(NSError *error, FBXCTestLogger *logger)
{
  fputs(error.localizedDescription.UTF8String, stderr);

  NSString *lastLines = [logger allLinesOfOutput];
  if (lastLines) {
    fputs(lastLines.UTF8String, stderr);
  }

  fflush(stderr);
  return NO;
}

@end
