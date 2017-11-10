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

static NSString *XcodebuildEnvironmentTargetUDID = @"XCTESTBOOTSTRAP_TARGET_UDID";

@interface FBXcodeBuildOperation ()

@property (nonatomic, strong, readonly) FBFuture<FBTask *> *future;
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

@end

@implementation FBXcodeBuildOperation

+ (instancetype)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath
{
  FBFuture<FBTask *> *future = [self createTaskFuture:configuraton xcodeBuildPath:xcodeBuildPath testRunFilePath:testRunFilePath target:target];
  return [[self alloc] initWithFuture:future asyncQueue:target.asyncQueue];
}

+ (FBFuture<FBTask *> *)createTaskFuture:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath target:(id<FBiOSTarget>)target
{
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];
  [arguments addObjectsFromArray:@[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", target.udid],
  ]];

  if (configuraton.resultBundlePath) {
    [arguments addObjectsFromArray:@[
      @"-resultBundlePath",
      configuraton.resultBundlePath,
    ]];
  }

  for (NSString *test in configuraton.testsToRun) {
    [arguments addObject:[NSString stringWithFormat:@"-only-testing:%@", test]];
  }

  for (NSString *test in configuraton.testsToSkip) {
    [arguments addObject:[NSString stringWithFormat:@"-skip-testing:%@", test]];
  }

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildEnvironmentTargetUDID] = target.udid;

  return [[[[[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment]
    withStdOutToLogger:target.logger]
    withStdErrToLogger:target.logger]
    buildFuture];
}

- (instancetype)initWithFuture:(FBFuture<FBTask *> *)future asyncQueue:(dispatch_queue_t)asyncQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _future = future;
  _asyncQueue = asyncQueue;

  return self;
}

#pragma mark FBTerminationAwaitable

- (FBFuture<NSNull *> *)completed
{
  return [self.future
    onQueue:self.asyncQueue fmap:^(FBTask *task) {
      NSError *error = task.error;
      if (error) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeTestOperation;
}

- (void)terminate
{
  [self.future cancel];
}

#pragma mark Public Methods

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.future awaitWithTimeout:timeout error:error] != nil;
}

#pragma mark Public

+ (BOOL)terminateReparentedXcodeBuildProcessesForTarget:(id<FBiOSTarget>)target processFetcher:(FBProcessFetcher *)processFetcher error:(NSError **)error
{
  NSArray<FBProcessInfo *> *processes = [processFetcher processesWithProcessName:@"xcodebuild"];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher workQueue:target.workQueue logger:target.logger];
  NSString *udid = target.udid;
  for (FBProcessInfo *process in processes) {
    if (![process.environment[XcodebuildEnvironmentTargetUDID] isEqualToString:udid]) {
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
      @"EnvironmentVariables": testLaunch.applicationLaunchConfiguration.environment,
      @"TestingEnvironmentVariables": @{
        @"DYLD_FRAMEWORK_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
        @"DYLD_LIBRARY_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
      },
    }
  };
}

@end
