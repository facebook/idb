/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestBootstrapper.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBXCTestKit/FBXCTestKit.h>

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
  FBControlCoreGlobalConfiguration.defaultLogger = _logger;
  FBControlCoreGlobalConfiguration.debugLoggingEnabled = YES;

  return self;
}

- (BOOL)bootstrap
{
  NSError *error;
  NSString *workingDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];

  if (![NSFileManager.defaultManager createDirectoryAtPath:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [self printErrorMessage:error];
  }

  NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
  arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];
  [self.logger.debug logFormat:@"fbxctest arguments: %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];
  FBXCTestConfiguration *configuration = [FBXCTestConfiguration
    configurationFromArguments:arguments
    processUnderTestEnvironment:@{}
    workingDirectory:workingDirectory
    error:&error];
  if (!configuration) {
    return [self printErrorMessage:error];
  }
  FBFileWriter *stdOutFileWriter = [FBFileWriter writerWithFileHandle:NSFileHandle.fileHandleWithStandardOutput blocking:YES];
  FBJSONTestReporter *reporter = [[FBJSONTestReporter new] initWithTestBundlePath:configuration.testBundlePath testType:configuration.testType logger:self.logger fileConsumer:stdOutFileWriter];
  FBXCTestContext *context = [FBXCTestContext contextWithReporter:reporter logger:self.logger];

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithConfiguration:configuration context:context];
  if (![testRunner executeWithError:&error]) {
    return [self printErrorMessage:error];
  }

  if (![NSFileManager.defaultManager removeItemAtPath:workingDirectory error:&error]) {
    return [self printErrorMessage:error];
  }

  return YES;
}


- (BOOL)printErrorMessage:(NSError *)error
{
  NSString *message = error.localizedDescription;
  if (message) {
    fputs(message.UTF8String, stderr);
  }
  message = [self.logger allLinesOfOutput];
  if (message) {
    fputs(message.UTF8String, stderr);
  }

  fflush(stderr);
  return NO;
}

@end
