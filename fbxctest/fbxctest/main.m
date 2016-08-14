// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

#import <FBXCTestKit/FBXCTestKit.h>

void handleError(NSError *error);

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *workingDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    if (![fileManager createDirectoryAtPath:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
      handleError(error);
      return 2;
    }

    FBTestRunConfiguration *configuration = [FBTestRunConfiguration new];
    if (![configuration loadWithArguments:[NSProcessInfo processInfo].arguments workingDirectory:workingDirectory error:&error]) {
      handleError(error);
      return 2;
    }

    FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
    if(![testRunner executeTestsWithError:&error]) {
      handleError(error);
      return 2;
    }

    if (![fileManager removeItemAtPath:workingDirectory error:&error]) {
      handleError(error);
      return 2;
    }
  }
  return 0;
}

void handleError(NSError *error)
{
  NSLog(@"%@", error.localizedDescription);
}
