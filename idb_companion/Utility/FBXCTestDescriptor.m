/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDescriptor.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBIDBError.h"
#import "FBIDBTestOperation.h"
#import "FBTestApplicationsPair.h"
#import "FBTemporaryDirectory.h"
#import "FBIDBStorageManager.h"

static FBApplicationLaunchConfiguration *BuildAppLaunchConfig(NSString *bundleID, NSDictionary<NSString *, NSString *> *environment, NSArray<NSString *> * arguments, id<FBControlCoreLogger> logger)
{
  NSError *error = nil;
  FBProcessOutputConfiguration *processOutput = [FBProcessOutputConfiguration
    configurationWithStdOut:[FBLoggingDataConsumer consumerWithLogger:logger]
    stdErr:[FBLoggingDataConsumer consumerWithLogger:logger]
    error:&error];
  NSCAssert(processOutput, @"Could not build process output %@", error);
  return [FBApplicationLaunchConfiguration configurationWithBundleID:bundleID
    bundleName:nil
    arguments:arguments ?: @[]
    environment:environment ?: @{}
    output:processOutput
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

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

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[FBXCTestShimConfiguration
    defaultShimConfiguration]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBXCTestShimConfiguration *shims) {
      NSError *error = nil;
      NSURL *workingDirectory = [temporaryDirectory ephemeralTemporaryDirectory];
      if (![NSFileManager.defaultManager createDirectoryAtURL:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [FBFuture futureWithError:error];
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
        configurationWithShims:shims
        environment:self.environment
        workingDirectory:workingDirectory.path
        testBundlePath:testDescriptor.testBundle.path
        waitForDebugger:NO
        timeout:timeout
        testFilter:testFilter
        mirroring:FBLogicTestMirrorFileLogs];

      return [self startTestExecution:configuration target:target reporter:reporter logger:logger];
    }];
}

- (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [[self
    executorWithConfiguration:configuration target:target]
    onQueue:target.workQueue fmap:^(id<FBXCTestProcessExecutor> executor) {
      FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:reporter logger:logger];
      FBLogicTestRunStrategy *runner = [FBLogicTestRunStrategy strategyWithExecutor:executor configuration:configuration reporter:adapter logger:logger];
      FBFuture<NSNull *> *completed = [runner execute];
      if (completed.error) {
        return [FBFuture futureWithError:completed.error];
      }
    FBIDBTestOperation *operation = [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:nil coveragePath:nil binaryPath:nil reporter:reporter logger:logger completed:completed queue:target.workQueue];
      return [FBFuture futureWithResult:operation];
    }];
}

- (FBFuture<id<FBXCTestProcessExecutor>> *)executorWithConfiguration:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  id<FBXCTestProcessExecutor> executor = nil;
  if ([target isKindOfClass:FBSimulator.class]) {
    executor = [FBSimulatorXCTestProcessExecutor executorWithSimulator:(FBSimulator *)target shims:configuration.shims];
  } else if ([target isKindOfClass:FBMacDevice.class]) {
    executor = [FBMacXCTestProcessExecutor executorWithMacDevice:(FBMacDevice *)target shims:configuration.shims];
  }

  if (!executor) {
    return [[FBIDBError
      describeFormat:@"%@ does not support logic tests", target]
      failFuture];
  }
  return [FBFuture futureWithResult:executor];
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

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[testDescriptor
    testAppPairForRequest:self target:target]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBTestApplicationsPair *pair) {
      [logger logFormat:@"Obtaining launch configuration for App Pair %@ on descriptor %@", pair, testDescriptor];
      FBTestLaunchConfiguration *testConfig = [testDescriptor testConfigWithRunRequest:self testApps:pair logger:logger];
      [logger logFormat:@"Obtained launch configuration %@", testConfig];
      return [FBXCTestRunRequest_AppTest startTestExecution:testConfig target:target reporter:reporter logger:logger];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBTestLaunchConfiguration *)configuration target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBXCTestReporterAdapter *adapter = [FBXCTestReporterAdapter adapterWithReporter:reporter];
  return [[target installedApplicationWithBundleID:configuration.targetApplicationBundleID ?: configuration.applicationLaunchConfiguration.bundleID] onQueue:target.workQueue fmap:^(FBInstalledApplication *installedApp) {
    NSString *binaryPath = [FBProductBundleBuilder productBundleFromInstalledApplication:installedApp error:nil].binaryPath;
    return [[target
      startTestWithLaunchConfiguration:configuration reporter:adapter logger:logger]
      onQueue:target.workQueue map:^(id<FBiOSTargetContinuation> continuation) {
        return [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:configuration.resultBundlePath coveragePath:configuration.coveragePath binaryPath:binaryPath reporter:reporter logger:logger completed:continuation.completed queue:target.workQueue];
      }];
  }];
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
@synthesize appBundleID = _appBundleID;
@synthesize testHostAppBundleID = _testHostAppBundleID;
@synthesize environment = _environment;
@synthesize arguments = _arguments;
@synthesize testsToRun = _testsToRun;
@synthesize testsToSkip = _testsToSkip;
@synthesize testTimeout = _testTimeout;


#pragma mark Initializers

+ (instancetype)logicTestWithTestBundleID:(NSString *)testBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout  reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage
{
  return [[FBXCTestRunRequest_LogicTest alloc] initWithTestBundleID:testBundleID appBundleID:nil testHostAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
}

+ (instancetype)applicationTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip  testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage
{
  return [[FBXCTestRunRequest_AppTest alloc] initWithTestBundleID:testBundleID appBundleID:appBundleID testHostAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
}

+ (instancetype)uiTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout  reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage
{
  return [[FBXCTestRunRequest_UITest alloc] initWithTestBundleID:testBundleID appBundleID:appBundleID testHostAppBundleID:testHostAppBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
}

- (instancetype)initWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testBundleID = testBundleID;
  _appBundleID = appBundleID;
  _testHostAppBundleID = testHostAppBundleID;
  _environment = environment;
  _arguments = arguments;
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;
  _testTimeout = testTimeout;
  _reportActivities = reportActivities;
  _collectCoverage = collectCoverage;

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
    onQueue:target.workQueue fmap:^(id<FBXCTestDescriptor> descriptor) {
      return [self startWithTestDescriptor:descriptor target:target reporter:reporter logger:logger temporaryDirectory:temporaryDirectory];
    }];
}

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
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

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logger:(id<FBControlCoreLogger>)logger
{
  FBTestLaunchConfiguration *config = [[[[FBTestLaunchConfiguration
  configurationWithTestBundlePath:self.testBundle.path]
  withTestsToRun:request.testsToRun]
  withTestsToSkip:request.testsToSkip]
  withReportActivities:request.reportActivities];

  if (request.isUITest) {
    FBApplicationLaunchConfiguration *runnerLaunchConfig = BuildAppLaunchConfig(testApps.testHostApp.bundle.identifier, request.environment, request.arguments, logger);

    // Test config
    config = [[[[config
      withUITesting:YES]
      withApplicationLaunchConfiguration:runnerLaunchConfig]
      withTargetApplicationPath:testApps.applicationUnderTest.bundle.path]
      withTargetApplicationBundleID:testApps.applicationUnderTest.bundle.identifier];
  } else {
    FBApplicationLaunchConfiguration *launchConfig = BuildAppLaunchConfig(request.appBundleID, request.environment, request.arguments, logger);
    config = [config withApplicationLaunchConfiguration:launchConfig];
  }

  if (request.collectCoverage) {
    NSString *coverageFileName = [NSString stringWithFormat:@"coverage_%@.profraw", NSUUID.UUID.UUIDString];
    NSString *coveragePath = [self.targetAuxillaryDirectory stringByAppendingPathComponent:coverageFileName];
    config = [config withCoveragePath:coveragePath];
  }

  return config;
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

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logger:(id<FBControlCoreLogger>)logger
{
  FBApplicationLaunchConfiguration *launchConfig = BuildAppLaunchConfig(request.appBundleID, request.environment, request.arguments, logger);
  NSString *resultBundleName = [NSString stringWithFormat:@"resultbundle_%@", NSUUID.UUID.UUIDString];
  NSString *resultBundlePath = [self.targetAuxillaryDirectory stringByAppendingPathComponent:resultBundleName];

  return [[[[[[[[[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.testBundle.path]
    withTestHostPath:self.testHostBundle.path]
    withApplicationLaunchConfiguration:launchConfig]
    withXcodebuild:YES]
    withUITesting:request.isUITest]
    withXCTestRunProperties:[NSDictionary dictionaryWithContentsOfURL:self.url]]
    withTestsToRun:request.testsToRun]
    withTestsToSkip:request.testsToSkip]
    withResultBundlePath:resultBundlePath]
    withReportActivities:request.reportActivities];
}

@end
