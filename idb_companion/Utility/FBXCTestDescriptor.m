/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDescriptor.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBCodeCoverageRequest.h"
#import "FBIDBAppHostedTestConfiguration.h"
#import "FBIDBError.h"
#import "FBTestApplicationsPair.h"
#import "FBXCTestRunFileReader.h"
#import "FBXCTestRunRequest.h"

static FBFuture<FBApplicationLaunchConfiguration *> *BuildAppLaunchConfig(NSString *bundleID, NSDictionary<NSString *, NSString *> *environment, NSArray<NSString *> * arguments, id<FBControlCoreLogger> logger,  NSString * processLogDirectory, dispatch_queue_t queue)
{
  FBLoggingDataConsumer *stdOutConsumer = [FBLoggingDataConsumer consumerWithLogger:logger];
  FBLoggingDataConsumer *stdErrConsumer = [FBLoggingDataConsumer consumerWithLogger:logger];

  FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *stdOutFuture = [FBFuture futureWithResult:stdOutConsumer];
  FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *stdErrFuture = [FBFuture futureWithResult:stdErrConsumer];

  if (processLogDirectory) {
    FBXCTestLogger *mirrorLogger = [FBXCTestLogger defaultLoggerInDirectory:processLogDirectory];
    NSUUID *udid = NSUUID.UUID;
    stdOutFuture = [mirrorLogger logConsumptionToFile:stdOutConsumer outputKind:@"out" udid:udid logger:logger];
    stdErrFuture = [mirrorLogger logConsumptionToFile:stdErrConsumer outputKind:@"err" udid:udid logger:logger];
  }

  return [[FBFuture
    futureWithFutures:@[stdOutFuture, stdErrFuture]]
    onQueue:queue map:^ (NSArray<id<FBDataConsumer, FBDataConsumerLifecycle>> *outputs) {
      FBProcessIO *io = [[FBProcessIO alloc]
        initWithStdIn:nil
        stdOut:[FBProcessOutput outputForDataConsumer:outputs[0]]
        stdErr:[FBProcessOutput outputForDataConsumer:outputs[1]]];
      return [[FBApplicationLaunchConfiguration alloc]
        initWithBundleID:bundleID
        bundleName:nil
        arguments:arguments ?: @[]
        environment:environment ?: @{}
        waitForDebugger:NO
        io:io
        launchMode:FBApplicationLaunchModeFailIfRunning];
  }];
}

@interface FBXCTestBootstrapDescriptor ()

@property (nonatomic, strong, readonly) NSString *targetAuxillaryDirectory;

@end


@implementation FBXCTestBootstrapDescriptor

@synthesize url = _url;
@synthesize name = _name;
@synthesize testBundle = _testBundle;

#pragma mark Initializers

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBBundleDescriptor *)testBundle
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _url = url;
  _name = name;
  _testBundle = testBundle;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"xctestbootstrap descriptor for %@ %@ %@", self.url, self.name, self.testBundle];
}

#pragma mark Properties

- (NSString *)testBundleID
{
  return self.testBundle.identifier;
}

- (NSSet *)architectures
{
  return self.testBundle.binary.architectures;
}

#pragma mark Private

+ (FBFuture<NSNull *> *)killAllRunningApplications:(id<FBiOSTarget>)target
{
  id<FBApplicationCommands> commands = (id<FBApplicationCommands>) target;
  if (![commands conformsToProtocol:@protocol(FBApplicationCommands)]) {
    return [[FBIDBError
      describeFormat:@"%@ does not conform to FBApplicationCommands", commands]
      failFuture];
  }
  return [[[commands
    runningApplications]
    onQueue:target.workQueue fmap:^(NSDictionary<NSString *, FBProcessInfo *> *runningApplications) {
      NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
      for (NSString *bundleID in runningApplications) {
       [futures addObject:[commands killApplicationWithBundleID:bundleID]];
      }
      return [FBFuture futureWithFutures:futures];
    }]
    mapReplace:NSNull.null];
}

#pragma mark Public

- (FBFuture<NSNull *> *)setupWithRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target
{
  _targetAuxillaryDirectory = target.auxillaryDirectory;
  if (request.isLogicTest) {
    //Logic tests don't use an app to run
    //killing them is unnecessary for us.
    return FBFuture.empty;
  }

  // Kill all Running Applications to get back to a clean slate.
  return [[FBXCTestBootstrapDescriptor killAllRunningApplications:target] mapReplace:NSNull.null];
}

- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target
{
  if (request.isLogicTest) {
    return [FBFuture futureWithResult:[[FBTestApplicationsPair alloc] initWithApplicationUnderTest:nil testHostApp:nil]];
  }
  if (request.isUITest) {
    if (!request.appBundleID) {
      return [[FBIDBError
        describe:@"Request for UI Test, but no app_bundle_id provided"]
        failFuture];
    }
    NSString *testHostBundleID = request.testHostAppBundleID ?: @"com.apple.Preferences";
    return [[FBFuture
      futureWithFutures:@[
        [target installedApplicationWithBundleID:request.appBundleID],
        [target installedApplicationWithBundleID:testHostBundleID],
      ]]
      onQueue:target.asyncQueue map:^(NSArray<FBInstalledApplication *> *applications) {
        return [[FBTestApplicationsPair alloc] initWithApplicationUnderTest:applications[0] testHostApp:applications[1]];
      }];
  }
  NSString *bundleID = request.testHostAppBundleID ?: request.appBundleID;
  if (!bundleID) {
    return [[FBIDBError
      describe:@"Request for Application Test, but no app_bundle_id or test_host_app_bundle_id provided"]
      failFuture];
  }
  return [[target
    installedApplicationWithBundleID:bundleID]
    onQueue:target.asyncQueue map:^(FBInstalledApplication *application) {
      return [[FBTestApplicationsPair alloc] initWithApplicationUnderTest:nil testHostApp:application];
    }];
}

- (FBFuture<FBIDBAppHostedTestConfiguration *> *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logDirectoryPath:(NSString *)logDirectoryPath logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  BOOL uiTesting = NO;
  FBFuture<FBApplicationLaunchConfiguration *> *appLaunchConfigFuture = nil;
  if (request.isUITest) {
    appLaunchConfigFuture = BuildAppLaunchConfig(testApps.testHostApp.bundle.identifier, request.environment, request.arguments, logger, logDirectoryPath, queue);
    uiTesting = YES;
  } else {
    appLaunchConfigFuture = BuildAppLaunchConfig(request.appBundleID, request.environment, request.arguments, logger, logDirectoryPath, queue);
  }
  FBCodeCoverageConfiguration *coverageConfig = nil;
  if (request.coverageRequest.collect) {
    NSString *coverageDirName =[NSString stringWithFormat:@"coverage_%@", NSUUID.UUID.UUIDString];
    NSString *coverageDirPath = [self.targetAuxillaryDirectory stringByAppendingPathComponent:coverageDirName];
    coverageConfig = [[FBCodeCoverageConfiguration alloc] initWithDirectory:coverageDirPath format:request.coverageRequest.format];
  }

  return [appLaunchConfigFuture onQueue:queue map:^ FBIDBAppHostedTestConfiguration * (FBApplicationLaunchConfiguration *applicationLaunchConfiguration) {
    FBTestLaunchConfiguration *testLaunchConfig = [[FBTestLaunchConfiguration alloc]
      initWithTestBundle:self.testBundle
      applicationLaunchConfiguration:applicationLaunchConfiguration
      testHostBundle:testApps.testHostApp.bundle
      timeout:(request.testTimeout ? request.testTimeout.doubleValue : 0)
      initializeUITesting:uiTesting
      useXcodebuild:NO
      testsToRun:request.testsToRun
      testsToSkip:request.testsToSkip
      targetApplicationBundle:testApps.applicationUnderTest.bundle
      xcTestRunProperties:nil
      resultBundlePath:nil
      reportActivities:request.reportActivities
      coverageDirectoryPath:coverageConfig.coverageDirectory
      logDirectoryPath:logDirectoryPath];
    return [[FBIDBAppHostedTestConfiguration alloc] initWithTestLaunchConfiguration:testLaunchConfig coverageConfiguration:coverageConfig];
  }];
}

@end

@interface FBXCodebuildTestRunDescriptor ()

@property (nonatomic, strong, readonly) NSString *targetAuxillaryDirectory;

@end

@implementation FBXCodebuildTestRunDescriptor

@synthesize url = _url;
@synthesize name = _name;
@synthesize testBundle = _testBundle;

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBBundleDescriptor *)testBundle testHostBundle:(FBBundleDescriptor *)testHostBundle
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _url = url;
  _name = name;
  _testBundle = testBundle;
  _testHostBundle = testHostBundle;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"xcodebuild descriptor for %@ %@ %@ %@", self.url, self.name, self.testBundle, self.testHostBundle];
}

#pragma mark Properties

- (NSString *)testBundleID
{
  return self.testBundle.identifier;
}

- (NSSet *)architectures
{
  return self.testHostBundle.binary.architectures;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)setupWithRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target
{
  _targetAuxillaryDirectory = target.auxillaryDirectory;
  return FBFuture.empty;
}

- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target
{
  return [FBFuture futureWithResult:[[FBTestApplicationsPair alloc] initWithApplicationUnderTest:nil testHostApp:nil]];
}

- (FBFuture<FBIDBAppHostedTestConfiguration *> *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logDirectoryPath:(NSString *)logDirectoryPath logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  NSString *resultBundleName = [NSString stringWithFormat:@"resultbundle_%@", NSUUID.UUID.UUIDString];
  NSString *resultBundlePath = [self.targetAuxillaryDirectory stringByAppendingPathComponent:resultBundleName];

  NSError *error = nil;
  NSDictionary<NSString *, id> *properties = [FBXCTestRunFileReader readContentsOf:self.url expandPlaceholderWithPath:self.targetAuxillaryDirectory error:&error];
  if (!properties) {
    return [FBFuture futureWithError:error];
  }
  return [BuildAppLaunchConfig(request.appBundleID, request.environment, request.arguments, logger, nil, queue)
   onQueue:queue map:^ FBIDBAppHostedTestConfiguration * (FBApplicationLaunchConfiguration *launchConfig) {
    FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration alloc]
      initWithTestBundle:self.testBundle
      applicationLaunchConfiguration:launchConfig
      testHostBundle:self.testHostBundle
      timeout:0
      initializeUITesting:request.isUITest
      useXcodebuild:YES
      testsToRun:request.testsToRun
      testsToSkip:request.testsToSkip
      targetApplicationBundle:nil
      xcTestRunProperties:properties
      resultBundlePath:resultBundlePath
      reportActivities:request.reportActivities
      coverageDirectoryPath:nil
      logDirectoryPath:logDirectoryPath];
    return [[FBIDBAppHostedTestConfiguration alloc] initWithTestLaunchConfiguration:testLaunchConfiguration coverageConfiguration:nil];
  }];
}


@end
