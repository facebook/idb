/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXcodeBuildOperation.h"
#import "XCTestBootstrapError.h"

#import <FBControlCore/FBControlCore.h>

static NSString *XcodebuildEnvironmentTargetUDID = @"XCTESTBOOTSTRAP_TARGET_UDID";
static NSString *XcodebuildDestinationTimeoutSecs = @"180"; // How long xcodebuild should wait for the device to be available

@implementation FBXcodeBuildOperation

+ (FBFuture<FBTask *> *)operationWithUDID:(NSString *)udid configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];
  [arguments addObjectsFromArray:@[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", udid],
    @"-destination-timeout", XcodebuildDestinationTimeoutSecs,
  ]];

  if (configuration.resultBundlePath) {
    [arguments addObjectsFromArray:@[
      @"-resultBundlePath",
      configuration.resultBundlePath,
    ]];
  }

  for (NSString *test in configuration.testsToRun) {
    [arguments addObject:[NSString stringWithFormat:@"-only-testing:%@", test]];
  }

  for (NSString *test in configuration.testsToSkip) {
    [arguments addObject:[NSString stringWithFormat:@"-skip-testing:%@", test]];
  }

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildEnvironmentTargetUDID] = udid;

  [logger logFormat:@"Starting test with xcodebuild %@", [arguments componentsJoinedByString:@" "]];
  FBTaskBuilder *builder = [[[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment]
    withAcceptableTerminationStatusCodes:[NSSet setWithObjects:@0, @65, nil]];
  if (logger) {
    [builder withStdOutToLoggerAndErrorMessage:logger];
    [builder withStdErrToLoggerAndErrorMessage:logger];
  }
  return [[builder
    start]
    onQueue:queue map:^(FBTask *task) {
      [logger logFormat:@"Task started %@ for xcodebuild %@", task, [arguments componentsJoinedByString:@" "]];
      return task;
    }];
}

#pragma mark Public

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

+ (nullable NSString *)createXCTestRunFileAt:(NSString *)directory fromConfiguration:(FBTestLaunchConfiguration *)configuration error:(NSError **)error
{
  NSString *fileName = [NSProcessInfo.processInfo.globallyUniqueString stringByAppendingPathExtension:@"xctestrun"];
  NSString *path = [directory stringByAppendingPathComponent:fileName];

  NSDictionary<NSString *, id> *defaultTestRunProperties = [FBXcodeBuildOperation xctestRunProperties:configuration];

  NSDictionary<NSString *, id> *testRunProperties = configuration.xcTestRunProperties
  ? [self overwriteXCTestRunPropertiesWithBaseProperties:configuration.xcTestRunProperties newProperties:defaultTestRunProperties]
    : defaultTestRunProperties;

  if (![testRunProperties writeToFile:path atomically:false]) {
    return [[XCTestBootstrapError
      describeFormat:@"Failed to write to file %@", path]
      fail:error];
  }
  return path;
}

+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSArray<FBProcessInfo *> *processes = [self activeXcodebuildProcessesForUDID:udid processFetcher:processFetcher];
  if (processes.count == 0) {
    [logger logFormat:@"No processes for %@ to terminate", udid];
    return [FBFuture futureWithResult:@[]];
  }
  [logger logFormat:@"Terminating abandoned xcodebuild processes %@", [FBCollectionInformation oneLineDescriptionFromArray:processes]];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher workQueue:queue logger:logger];
  NSMutableArray<FBFuture<FBProcessInfo *> *> *futures = [NSMutableArray array];
  for (FBProcessInfo *process in processes) {
    FBFuture<FBProcessInfo *> *termination = [[strategy killProcess:process] mapReplace:process];
    [futures addObject:termination];
  }
  return [FBFuture futureWithFutures:futures];
}

+ (NSString *)xcodeBuildPathWithError:(NSError **)error
{
  NSString *path = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"/usr/bin/xcodebuild"];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return [[XCTestBootstrapError
      describeFormat:@"xcodebuild does not exist at expected path %@", path]
      fail:error];
  }
  return path;
}

+ (NSDictionary<NSString *, id> *)overwriteXCTestRunPropertiesWithBaseProperties:(NSDictionary<NSString *, id> *)baseProperties newProperties:(NSDictionary<NSString *, id> *)newProperties
{
  NSDictionary<NSString *, id> *defaultTestProperties = [newProperties objectForKey:@"StubBundleId"];
  NSMutableDictionary<NSString *, id> *mutableTestRunProperties = NSMutableDictionary.dictionary;
  for (NSString *testId in baseProperties) {
    NSMutableDictionary<NSString *, id> *mutableTestProperties = [[baseProperties objectForKey:testId] mutableCopy];
    for (id key in defaultTestProperties) {
      if ([mutableTestProperties objectForKey:key]) {
        mutableTestProperties[key] =  [defaultTestProperties objectForKey:key];
      }
    }
    mutableTestRunProperties[testId] = mutableTestProperties;
  }
  return [mutableTestRunProperties copy];
}

#pragma mark Private

+ (NSArray<FBProcessInfo *> *)activeXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher
{
  NSArray<FBProcessInfo *> *xcodebuildProcesses = [processFetcher processesWithProcessName:@"xcodebuild"];
  NSMutableArray<FBProcessInfo *> *relevantProcesses = [NSMutableArray array];
  for (FBProcessInfo *process in xcodebuildProcesses) {
    if (![process.environment[XcodebuildEnvironmentTargetUDID] isEqualToString:udid]) {
      continue;
    }
    [relevantProcesses addObject:process];
  }
  return relevantProcesses;
}

@end
