/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDescriptor.h"

#import "FBIDBError.h"
#import "FBTestApplicationsPair.h"

@implementation FBXCTestRunRequest

@synthesize isLogicTest = _isLogicTest;
@synthesize isUITest = _isUITest;
@synthesize testBundleID = _testBundleID;
@synthesize appBundleID = _appBundleID;
@synthesize testHostAppBundleID = _testHostAppBundleID;
@synthesize environment = _environment;
@synthesize arguments = _arguments;
@synthesize testsToRun = _testsToRun;
@synthesize testsToSkip = _testsToSkip;
@synthesize testTimeout = _testTimeout;


- (instancetype)initWithLogicTest:(BOOL)logicTest uiTest:(BOOL)uiTest testBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _isLogicTest = logicTest;
  _isUITest = uiTest;
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

@end

@implementation FBXCTestBootstrapDescriptor

@synthesize url = _url;
@synthesize name = _name;
@synthesize testBundle = _testBundle;

#pragma mark Initializers

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBApplicationBundle *)testBundle
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
  return self.testBundle.bundleID;
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

- (FBFuture<NSNull *> *)setupWithRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target
{
  if (request.isLogicTest) {
    //Logic tests don't use an app to run
    //killing them is unnecessary for us.
    return [FBFuture futureWithResult:NSNull.null];
  }

  // Kill all Running Applications to get back to a clean slate.
  return [[FBXCTestBootstrapDescriptor killAllRunningApplications:target] mapReplace:NSNull.null];
}

- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target
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

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(id<FBXCTestRunRequest>)request testApps:(FBTestApplicationsPair *)testApps
{
  if (request.isUITest) {
    FBApplicationLaunchConfiguration *runnerLaunchConfig = [self appLaunchConfigForBundleID:testApps.testHostApp.bundle.bundleID env:request.environment args:request.arguments];

    // Test config
    return [[[[[[[FBTestLaunchConfiguration
      configurationWithTestBundlePath:self.testBundle.path]
      withUITesting:YES]
      withApplicationLaunchConfiguration:runnerLaunchConfig]
      withTargetApplicationPath:testApps.applicationUnderTest.bundle.path]
      withTargetApplicationBundleID:testApps.applicationUnderTest.bundle.bundleID]
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

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBApplicationBundle *)testBundle testHostBundle:(FBApplicationBundle *)testHostBundle
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
  return self.testBundle.bundleID;
}

- (NSSet *)architectures
{
  return self.testHostBundle.binary.architectures;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)setupWithRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target
{
  _targetAuxillaryDirectory = target.auxillaryDirectory;
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target
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

- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(id<FBXCTestRunRequest>)request testApps:(FBTestApplicationsPair *)testApps
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
