/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXcodeBuildOperation.h"

#import <FBControlCore/FBControlCore.h>

static NSString *XcodebuildSubprocessEnvironmentIdentifier = @"FBDEVICECONTROL_DEVICE_IDENTIFIER";

@interface FBXcodeBuildOperation ()

@property (nonatomic, strong, nullable, readonly) FBTask *task;

@end

@implementation FBXcodeBuildOperation

+ (instancetype)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath
{
  FBTask *task = [self createTask:configuraton xcodeBuildPath:xcodeBuildPath testRunFilePath:testRunFilePath target:target];
  [task startAsynchronously];
  return [[self alloc] initWithTask:task];
}

+ (FBTask *)createTask:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath target:(id<FBiOSTarget>)target
{
  NSArray<NSString *> *arguments = @[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", target.udid],
  ];

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildSubprocessEnvironmentIdentifier] = target.udid;

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment]
    withStdOutToLogger:target.logger]
    withStdErrToLogger:target.logger]
    build];

  return task;
}

- (instancetype)initWithTask:(FBTask *)task
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;

  return self;
}

#pragma mark FBXCTestOperation

+ (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeTestOperation;
}

- (void)terminate
{
  [self.task terminate];
  _task = nil;
}

- (BOOL)hasTerminated
{
  return self.task.hasTerminated || self.task == nil;
}

#pragma mark Public Methods

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.task waitForCompletionWithTimeout:timeout error:error];
}

#pragma mark Public

+ (BOOL)terminateReparentedXcodeBuildProcessesForTarget:(id<FBiOSTarget>)target processFetcher:(FBProcessFetcher *)processFetcher error:(NSError **)error
{
  NSArray<FBProcessInfo *> *processes = [processFetcher processesWithProcessName:@"xcodebuild"];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher logger:target.logger];
  NSString *udid = target.udid;
  for (FBProcessInfo *process in processes) {
    if (![process.environment[XcodebuildSubprocessEnvironmentIdentifier] isEqualToString:udid]) {
      continue;
    }
    if (![strategy killProcess:process error:error]) {
      return NO;
    }
  }
  return YES;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch
{
  return @{
    @"StubBundleId" : @{
      @"TestHostPath" : testLaunch.testHostPath,
      @"TestBundlePath" : testLaunch.testBundlePath,
      @"UseUITargetAppProvidedByTests" : @YES,
      @"IsUITestBundle" : @YES,
      @"CommandLineArguments": testLaunch.applicationLaunchConfiguration.arguments,
      @"TestingEnvironmentVariables": @{
        @"DYLD_FRAMEWORK_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
        @"DYLD_LIBRARY_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
      },
    }
  };
}

@end
