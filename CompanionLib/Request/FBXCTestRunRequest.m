/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestRunRequest.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBIDBError.h"
#import "FBXCTestDescriptor.h"
#import "FBCodeCoverageRequest.h"
#import "FBXCTestReporterConfiguration.h"
#import "FBIDBAppHostedTestConfiguration.h"
#import "FBIDBTestOperation.h"
#import "FBIDBStorageManager.h"

static const NSTimeInterval FBLogicTestTimeout = 60 * 60; //Aprox. an hour.


@interface FBXCTestRunRequest_LogicTest : FBXCTestRunRequest

@end

@implementation FBXCTestRunRequest_LogicTest

- (BOOL)isLogicTest
{
  return YES;
}

- (BOOL)isUITest
{
  return NO;
}

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor logDirectoryPath:(NSString *)logDirectoryPath reportActivities:(BOOL)reportActivities target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  NSError *error = nil;
  NSURL *workingDirectory = [temporaryDirectory ephemeralTemporaryDirectory];
  if (![NSFileManager.defaultManager createDirectoryAtURL:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [FBFuture futureWithError:error];
  }

  FBCodeCoverageConfiguration *coverageConfig = nil;
  if (self.coverageRequest.collect) {
    NSURL *dir = [temporaryDirectory ephemeralTemporaryDirectory];
    NSString *coverageDirName =[NSString stringWithFormat:@"coverage_%@", NSUUID.UUID.UUIDString];
    NSString *coverageDirPath = [dir.path stringByAppendingPathComponent:coverageDirName];
    if (![NSFileManager.defaultManager createDirectoryAtPath:coverageDirPath withIntermediateDirectories:YES attributes:nil error:&error]) {
      return [FBFuture futureWithError:error];
    }
    coverageConfig = [[FBCodeCoverageConfiguration alloc] initWithDirectory:coverageDirPath format:self.coverageRequest.format enableContinuousCoverageCollection:self.coverageRequest.shouldEnableContinuousCoverageCollection];
  }

  NSString *testFilter = nil;
  NSArray<NSString *> *testsToSkip = self.testsToSkip.allObjects ?: @[];
  if (testsToSkip.count > 0) {
    return [[FBXCTestError
      describeFormat:@"'Tests to Skip' %@ provided, but Logic Tests to not support this.", [FBCollectionInformation oneLineDescriptionFromArray:testsToSkip]]
      failFuture];
  }
  NSArray<NSString *> *testsToRun = self.testsToRun.allObjects ?: @[];
  if (testsToRun.count > 1){
    return [[FBXCTestError
      describeFormat:@"More than one 'Tests to Run' %@ provided, but only one 'Tests to Run' is supported.", [FBCollectionInformation oneLineDescriptionFromArray:testsToRun]]
      failFuture];
  }
  testFilter = testsToRun.firstObject;

  NSTimeInterval timeout = self.testTimeout.boolValue ? self.testTimeout.doubleValue : FBLogicTestTimeout;
  FBLogicTestConfiguration *configuration = [FBLogicTestConfiguration
    configurationWithEnvironment:self.environment
    workingDirectory:workingDirectory.path
    testBundlePath:testDescriptor.testBundle.path
    waitForDebugger:self.waitForDebugger
    timeout:timeout
    testFilter:testFilter
    mirroring:FBLogicTestMirrorFileLogs
    coverageConfiguration:coverageConfig
    binaryPath:testDescriptor.testBundle.binary.path
    logDirectoryPath:logDirectoryPath
    architectures:testDescriptor.architectures];

  return [self startTestExecution:configuration target:target reporter:reporter logger:logger];
}

- (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:reporter logger:logger];
  FBLogicTestRunStrategy *runner = [[FBLogicTestRunStrategy alloc] initWithTarget:(id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands>)target configuration:configuration reporter:adapter logger:logger];
  FBFuture<NSNull *> *completed = [runner execute];
  if (completed.error) {
    return [FBFuture futureWithError:completed.error];
  }
  FBXCTestReporterConfiguration *reporterConfiguration = [[FBXCTestReporterConfiguration alloc]
    initWithResultBundlePath:nil
    coverageConfiguration:configuration.coverageConfiguration
    logDirectoryPath:configuration.logDirectoryPath
    binariesPaths:@[configuration.binaryPath]
    reportAttachments:self.reportAttachments
    reportResultBundle:self.collectResultBundle];
  FBIDBTestOperation *operation = [[FBIDBTestOperation alloc]
    initWithConfiguration:configuration
    reporterConfiguration:reporterConfiguration
    reporter:reporter
    logger:logger
    completed:completed
    queue:target.workQueue];
  return [FBFuture futureWithResult:operation];
}

@end

@interface FBXCTestRunRequest_AppTest : FBXCTestRunRequest

@end

@implementation FBXCTestRunRequest_AppTest

- (BOOL)isLogicTest
{
  return NO;
}

- (BOOL)isUITest
{
  return NO;
}

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor logDirectoryPath:(NSString *)logDirectoryPath reportActivities:(BOOL)reportActivities target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[[testDescriptor
    testAppPairForRequest:self target:target]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBAppHostedTestConfiguration *> * (FBTestApplicationsPair *pair) {
      [logger logFormat:@"Obtaining launch configuration for App Pair %@ on descriptor %@", pair, testDescriptor];
      return [testDescriptor testConfigWithRunRequest:self testApps:pair logDirectoryPath:logDirectoryPath logger:logger queue:target.workQueue];
    }]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBIDBAppHostedTestConfiguration *appHostedTestConfig) {
      [logger logFormat:@"Obtained app-hosted test configuration %@", appHostedTestConfig];
      return [FBXCTestRunRequest_AppTest startTestExecution:appHostedTestConfig reportAttachments:self.reportAttachments target:target reporter:reporter logger:logger reportResultBundle:self.collectResultBundle];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBIDBAppHostedTestConfiguration *)configuration reportAttachments:(BOOL)reportAttachments target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger reportResultBundle:(BOOL)reportResultBundle
{
  FBTestLaunchConfiguration *testLaunchConfiguration = configuration.testLaunchConfiguration;
  FBCodeCoverageConfiguration *coverageConfiguration = configuration.coverageConfiguration;

  NSMutableArray<NSString *> *binariesPaths = NSMutableArray.array;
  NSString *binaryPath = testLaunchConfiguration.testBundle.binary.path;
  if (binaryPath) {
    [binariesPaths addObject:binaryPath];
  }
  binaryPath = testLaunchConfiguration.testHostBundle.binary.path;
  if (binaryPath) {
    [binariesPaths addObject:binaryPath];
  }
  binaryPath = testLaunchConfiguration.targetApplicationBundle.binary.path;
  if (binaryPath) {
    [binariesPaths addObject:binaryPath];
  }

  FBFuture<NSNull *> *testCompleted = [target runTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger];
  FBXCTestReporterConfiguration *reporterConfiguration = [[FBXCTestReporterConfiguration alloc]
    initWithResultBundlePath:testLaunchConfiguration.resultBundlePath
    coverageConfiguration:coverageConfiguration
    logDirectoryPath:testLaunchConfiguration.logDirectoryPath
    binariesPaths:binariesPaths
    reportAttachments:reportAttachments
    reportResultBundle:reportResultBundle];
  return [FBFuture futureWithResult:[[FBIDBTestOperation alloc]
    initWithConfiguration:testLaunchConfiguration
    reporterConfiguration:reporterConfiguration
    reporter:reporter
    logger:logger
    completed:testCompleted
    queue:target.workQueue]];
}

@end

@interface FBXCTestRunRequest_UITest : FBXCTestRunRequest_AppTest

@end

@implementation FBXCTestRunRequest_UITest

- (BOOL)isLogicTest
{
  return NO;
}

- (BOOL)isUITest
{
  return YES;
}

@end







@implementation FBXCTestRunRequest

@synthesize testBundleID = _testBundleID;
@synthesize testHostAppBundleID = _testHostAppBundleID;
@synthesize environment = _environment;
@synthesize arguments = _arguments;
@synthesize testsToRun = _testsToRun;
@synthesize testsToSkip = _testsToSkip;
@synthesize testTimeout = _testTimeout;
@synthesize collectResultBundle = _collectResultBundle;


#pragma mark Initializers

+ (instancetype)logicTestWithTestBundleID:(NSString *)testBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle
{
  return [[FBXCTestRunRequest_LogicTest alloc] initWithTestBundleID:testBundleID testHostAppBundleID:nil testTargetAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverageRequest collectLogs:collectLogs waitForDebugger:waitForDebugger collectResultBundle:collectResultBundle];
}

+ (instancetype)applicationTestWithTestBundleID:(NSString *)testBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle
{
  return [[FBXCTestRunRequest_AppTest alloc] initWithTestBundleID:testBundleID testHostAppBundleID:testHostAppBundleID testTargetAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverageRequest collectLogs:collectLogs waitForDebugger:waitForDebugger collectResultBundle:collectResultBundle];
}

+ (instancetype)uiTestWithTestBundleID:(NSString *)testBundleID testHostAppBundleID:(NSString *)testHostAppBundleID testTargetAppBundleID:(NSString *)testTargetAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs collectResultBundle:(BOOL)collectResultBundle
{
  return [[FBXCTestRunRequest_UITest alloc] initWithTestBundleID:testBundleID testHostAppBundleID:testHostAppBundleID testTargetAppBundleID:testTargetAppBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverageRequest collectLogs:collectLogs waitForDebugger:NO collectResultBundle:collectResultBundle];
}

- (instancetype)initWithTestBundleID:(NSString *)testBundleID testHostAppBundleID:(NSString *)testHostAppBundleID testTargetAppBundleID:(NSString *)testTargetAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testBundleID = testBundleID;
  _testHostAppBundleID = testHostAppBundleID;
  _testTargetAppBundleID = testTargetAppBundleID;
  _environment = environment;
  _arguments = arguments;
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;
  _testTimeout = testTimeout;
  _reportActivities = reportActivities;
  _reportAttachments = reportAttachments;
  _coverageRequest = coverageRequest;
  _collectLogs = collectLogs;
  _waitForDebugger = waitForDebugger;
  _collectResultBundle = collectResultBundle;

  return self;
}

- (BOOL)isLogicTest
{
  return NO;
}

- (BOOL)isUITest
{
  return NO;
}

- (FBFuture<FBIDBTestOperation *> *)startWithBundleStorageManager:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[self
    fetchAndSetupDescriptorWithBundleStorage:bundleStorage target:target]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (id<FBXCTestDescriptor> descriptor) {
      NSString *logDirectoryPath = nil;
      if (self.collectLogs) {
        NSError *error;
        NSURL *directory = [temporaryDirectory ephemeralTemporaryDirectory];
        if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
          return [FBFuture futureWithError:error];
        }
        logDirectoryPath = directory.path;
      }
      return [self startWithTestDescriptor:descriptor logDirectoryPath:logDirectoryPath reportActivities:self.reportActivities target:target reporter:reporter logger:logger temporaryDirectory:temporaryDirectory];
    }];
}

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor logDirectoryPath:(NSString *)logDirectoryPath reportActivities:(BOOL)reportActivities target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[FBIDBError
    describeFormat:@"%@ not implemented in abstract base class", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<id<FBXCTestDescriptor>> *)fetchAndSetupDescriptorWithBundleStorage:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target
{
  NSError *error = nil;
  id<FBXCTestDescriptor> testDescriptor = [bundleStorage testDescriptorWithID:self.testBundleID error:&error];
  if (!testDescriptor) {
    return [FBFuture futureWithError:error];
  }
  return [[testDescriptor setupWithRequest:self target:target] mapReplace:testDescriptor];
}

@end
