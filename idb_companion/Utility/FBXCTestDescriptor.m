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

static const NSTimeInterval FBLogicTestTimeout = 60 * 60; //Aprox. an hour.

@interface FBFuture (FBXCTestDescriptor)

- (instancetype)idb_appendErrorLogging:(FBIDBTestOperation *)operation;

@end

@implementation FBFuture (FBXCTestDescriptor)

- (instancetype)idb_appendErrorLogging:(FBIDBTestOperation *)operation
{
  return [self onQueue:operation.queue chain:^(FBFuture *future) {
    if (!future.error) {
      return future;
    }
    return [[FBIDBError
      describeFormat:@"%@:%@", future.error.localizedDescription, operation.logBuffer.lines]
      failFuture];
  }];
}

@end

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

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
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

      return [self startTestExecution:configuration target:target];
    }];
}

- (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  return [[self
    executorWithConfiguration:configuration target:target]
    onQueue:target.workQueue fmap:^(id<FBXCTestProcessExecutor> executor) {
      id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
      id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:logBuffer];
      FBConsumableXCTestReporter *reporter = [FBConsumableXCTestReporter new];
      FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:reporter logger:logger];
      FBLogicTestRunStrategy *runner = [FBLogicTestRunStrategy strategyWithExecutor:executor configuration:configuration reporter:adapter logger:logger];
      FBFuture<NSNull *> *completed = [runner execute];
      if (completed.error) {
        return [FBFuture futureWithError:completed.error];
      }
      FBIDBTestOperation *operation = [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:nil reporter:reporter logBuffer:logBuffer completed:completed queue:target.workQueue];
      return [[FBFuture futureWithResult:operation] idb_appendErrorLogging:operation];
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

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[testDescriptor
    testAppPairForRequest:self target:target]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBTestApplicationsPair *pair) {
      [target.logger logFormat:@"Obtaining launch configuration for App Pair %@ on descriptor %@", pair, testDescriptor];
      FBTestLaunchConfiguration *testConfig = [testDescriptor testConfigWithRunRequest:self testApps:pair];
      [target.logger logFormat:@"Obtained launch configuration %@", testConfig];
      return [FBXCTestRunRequest_AppTest startTestExecution:testConfig target:target];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)startTestExecution:(FBTestLaunchConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:logBuffer];
  FBConsumableXCTestReporter *reporter = [FBConsumableXCTestReporter new];
  FBXCTestReporterAdapter *adapter = [FBXCTestReporterAdapter adapterWithReporter:reporter];
  return [[target
    startTestWithLaunchConfiguration:configuration reporter:adapter logger:logger]
    onQueue:target.workQueue fmap:^(id<FBiOSTargetContinuation> continuation) {
      FBIDBTestOperation *operation = [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:configuration.resultBundlePath reporter:reporter logBuffer:logBuffer completed:continuation.completed queue:target.workQueue];
      return [[FBFuture futureWithResult:operation] idb_appendErrorLogging:operation];
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

+ (instancetype)logicTestWithTestBundleID:(NSString *)testBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout
{
  return [[FBXCTestRunRequest_LogicTest alloc] initWithTestBundleID:testBundleID appBundleID:nil testHostAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout];
}

+ (instancetype)applicationTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout
{
  return [[FBXCTestRunRequest_AppTest alloc] initWithTestBundleID:testBundleID appBundleID:appBundleID testHostAppBundleID:nil environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout];
}

+ (instancetype)uiTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout
{
  return [[FBXCTestRunRequest_UITest alloc] initWithTestBundleID:testBundleID appBundleID:appBundleID testHostAppBundleID:testHostAppBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout];
}

- (instancetype)initWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout
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

- (FBFuture<FBIDBTestOperation *> *)startWithBundleStorageManager:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[self
    fetchAndSetupDescriptorWithBundleStorage:bundleStorage target:target]
    onQueue:target.workQueue fmap:^(id<FBXCTestDescriptor> descriptor) {
      return [self startWithTestDescriptor:descriptor target:target temporaryDirectory:temporaryDirectory];
    }];
}

- (FBFuture<FBIDBTestOperation *> *)startWithTestDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
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

- (FBApplicationLaunchConfiguration *)appLaunchConfigForBundleID:(NSString *)bundleID env:(NSDictionary<NSString *, NSString *> *)env args:(NSArray<NSString *> *)args
{
  return [FBApplicationLaunchConfiguration configurationWithBundleID:bundleID
    bundleName:nil
    arguments:args ?: @[]
    environment:env ?: @{}
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

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

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps
{
  if (request.isUITest) {
    FBApplicationLaunchConfiguration *runnerLaunchConfig = [self appLaunchConfigForBundleID:testApps.testHostApp.bundle.identifier env:request.environment args:request.arguments];

    // Test config
    return [[[[[[[FBTestLaunchConfiguration
      configurationWithTestBundlePath:self.testBundle.path]
      withUITesting:YES]
      withApplicationLaunchConfiguration:runnerLaunchConfig]
      withTargetApplicationPath:testApps.applicationUnderTest.bundle.path]
      withTargetApplicationBundleID:testApps.applicationUnderTest.bundle.identifier]
      withTestsToRun:request.testsToRun]
      withTestsToSkip:request.testsToSkip];
  } else {
    FBApplicationLaunchConfiguration *launchConfig = [self appLaunchConfigForBundleID:request.appBundleID env:request.environment args:request.arguments];

    return [[[[FBTestLaunchConfiguration
      configurationWithTestBundlePath:self.testBundle.path]
      withApplicationLaunchConfiguration:launchConfig]
      withTestsToRun:request.testsToRun]
      withTestsToSkip:request.testsToSkip];
  }
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

- (FBApplicationLaunchConfiguration *)appLaunchConfigForBundleID:(NSString *)bundleID env:(NSDictionary<NSString *, NSString *> *)env args:(NSArray<NSString *> *)args
{
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:bundleID
    bundleName:nil
    arguments:args ?: @[]
    environment:env ?: @{}
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps
{
  FBApplicationLaunchConfiguration *launchConfig = [self appLaunchConfigForBundleID:request.appBundleID env:request.environment args:request.arguments];
  NSString *resultBundleName = [NSString stringWithFormat:@"resultbundle_%@", NSUUID.UUID.UUIDString];
  NSString *resultBundlePath = [self.targetAuxillaryDirectory stringByAppendingPathComponent:resultBundleName];

  return [[[[[[[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.testBundle.path]
    withTestHostPath:self.testHostBundle.path]
    withApplicationLaunchConfiguration:launchConfig]
    withUITesting:request.isUITest]
    withXCTestRunProperties:[NSDictionary dictionaryWithContentsOfURL:self.url]]
    withTestsToRun:request.testsToRun]
    withTestsToSkip:request.testsToSkip]
    withResultBundlePath:resultBundlePath];
}

@end
