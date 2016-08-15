// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestBootstrapper.h"
#import "FBJSONTestReporter.h"
#import "FBTestRunConfiguration.h"
#import "FBXCTestRunner.h"

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
    handleError(error);
    return NO;
  }

  FBTestRunConfiguration *configuration = [FBTestRunConfiguration new];
  if (![configuration loadWithArguments:[NSProcessInfo processInfo].arguments
                       workingDirectory:workingDirectory
                                  error:&error]) {
    handleError(error);
    return NO;
  }

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  if (![testRunner executeTestsWithError:&error]) {
    handleError(error);
    return NO;
  }

  if (![fileManager removeItemAtPath:workingDirectory error:&error]) {
    handleError(error);
    return NO;
  }

  return YES;
}

static inline void handleError(NSError *error)
{
  NSLog(@"%@", error.localizedDescription);
}

@end
