/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestProcess.h"
#import "FBXCTestProcessExecutor.h"
#import "XCTestBootstrapError.h"

FBXCTestType const FBXCTestTypeApplicationTest = FBXCTestTypeApplicationTestValue;
FBXCTestType const FBXCTestTypeLogicTest = @"logic-test";
FBXCTestType const FBXCTestTypeListTest = @"list-test";
FBXCTestType const FBXCTestTypeUITest = @"ui-test";

@implementation FBXCTestConfiguration

#pragma mark Initializers

- (instancetype)initWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _shims = shims;
  _processUnderTestEnvironment = environment ?: @{};
  _workingDirectory = workingDirectory;
  _testBundlePath = testBundlePath;
  _waitForDebugger = waitForDebugger;

  NSString *timeoutFromEnv = NSProcessInfo.processInfo.environment[@"FB_TEST_TIMEOUT"];
  if (timeoutFromEnv) {
    _testTimeout = timeoutFromEnv.intValue;
  } else {
    _testTimeout = timeout > 0 ? timeout : [self defaultTimeout];
  }

  return self;
}

#pragma mark Public

- (NSTimeInterval)defaultTimeout
{
  return 500;
}

- (NSString *)testType
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSDictionary<NSString *, NSString *> *)buildEnvironmentWithEntries:(NSDictionary<NSString *, NSString *> *)entries
{
  NSMutableDictionary<NSString *, NSString *> *parentEnvironment = NSProcessInfo.processInfo.environment.mutableCopy;
  [parentEnvironment removeObjectsForKeys:@[
    @"XCTestConfigurationFilePath",
  ]];

  NSMutableDictionary<NSString *, NSString *> *environmentOverrides = [NSMutableDictionary dictionary];
  NSString *xctoolTestEnvPrefix = @"XCTOOL_TEST_ENV_";
  for (NSString *key in parentEnvironment) {
    if ([key hasPrefix:xctoolTestEnvPrefix]) {
      NSString *childKey = [key substringFromIndex:xctoolTestEnvPrefix.length];
      environmentOverrides[childKey] = parentEnvironment[key];
    }
  }
  [environmentOverrides addEntriesFromDictionary:entries];
  NSMutableDictionary<NSString *, NSString *> *environment = parentEnvironment.mutableCopy;
  for (NSString *key in environmentOverrides) {
    NSString *childKey = key;
    environment[childKey] = environmentOverrides[key];
  }
  return environment.copy;
}

#pragma mark NSObject

- (NSString *)description
{
  return [FBCollectionInformation oneLineDescriptionFromDictionary:self.jsonSerializableRepresentation];
}

- (BOOL)isEqual:(FBXCTestConfiguration *)object
{
  // Class must match exactly in the class-cluster
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return (self.shims == object.shims || [self.shims isEqual:object.shims])
      && (self.processUnderTestEnvironment == object.processUnderTestEnvironment || [self.processUnderTestEnvironment isEqualToDictionary:object.processUnderTestEnvironment])
      && (self.workingDirectory == object.workingDirectory || [self.workingDirectory isEqualToString:object.workingDirectory])
      && (self.testBundlePath == object.testBundlePath || [self.testBundlePath isEqualToString:object.testBundlePath])
      && (self.testType == object.testType || [self.testType isEqualToString:object.testType])
      && (self.waitForDebugger == object.waitForDebugger)
      && (self.testTimeout == object.testTimeout);
}

- (NSUInteger)hash
{
  return self.shims.hash ^ self.processUnderTestEnvironment.hash ^ self.workingDirectory.hash ^ self.testBundlePath.hash ^ self.testType.hash ^ ((NSUInteger) self.waitForDebugger) ^ ((NSUInteger) self.testTimeout);
}

#pragma mark JSON

static NSString *const KeyEnvironment = @"environment";
static NSString *const KeyListTestsOnly = @"list_only";
static NSString *const KeyOSLogPath = @"os_log_path";
static NSString *const KeyRunnerAppPath = @"test_host_path";
static NSString *const KeyRunnerTargetPath = @"test_target_path";
static NSString *const KeyShims = @"shims";
static NSString *const KeyTestArtifactsFilenameGlobs = @"test_artifacts_filename_globs";
static NSString *const KeyTestBundlePath = @"test_bundle_path";
static NSString *const KeyTestFilter = @"test_filter";
static NSString *const KeyTestMirror = @"test_mirror";
static NSString *const KeyTestTimeout = @"test_timeout";
static NSString *const KeyTestType = @"test_type";
static NSString *const KeyVideoRecordingPath = @"video_recording_path";
static NSString *const KeyWaitForDebugger = @"wait_for_debugger";
static NSString *const KeyWorkingDirectory = @"working_directory";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyEnvironment: self.processUnderTestEnvironment,
    KeyWorkingDirectory: self.workingDirectory,
    KeyTestBundlePath: self.testBundlePath,
    KeyTestType: self.testType,
    KeyListTestsOnly: @NO,
    KeyWaitForDebugger: @(self.waitForDebugger),
    KeyTestTimeout: @(self.testTimeout),
  };
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end

@implementation FBListTestConfiguration {
  NSString *_runnerAppPath;
}

#pragma mark Initializers

+ (instancetype)configurationWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath runnerAppPath:(nullable NSString *)runnerAppPath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout
{
  return [[FBListTestConfiguration alloc] initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath runnerAppPath:runnerAppPath waitForDebugger:waitForDebugger timeout:timeout];
}

- (instancetype)initWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath runnerAppPath:(nullable NSString *)runnerAppPath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout
{
  self = [super initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
  if (!self) {
    return nil;
  }

  _runnerAppPath = runnerAppPath;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return FBXCTestTypeListTest;
}

- (FBFuture<id<FBLaunchedProcess>> *)listTestProcessWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor logger:(id<FBControlCoreLogger>)logger
{
  if ([FBBundleDescriptor isApplicationAtPath:_runnerAppPath]) {
    // List test for app test bundle, so we use app binary instead of xctest to load test bundle.
    NSString *xcTestFrameworkPath =
    [[FBXcodeConfiguration.developerDirectory
      stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform"]
      stringByAppendingPathComponent:@"Developer/Library/Frameworks/XCTest.framework"];

    // Since we spawn process using app binary directly without installation, we need to manully copy
    // xctest framework to app's rpath so it can be found by dyld when we load test bundle later.
    [FBListTestConfiguration copyFrameworkToApplicationAtPath:_runnerAppPath frameworkPath:xcTestFrameworkPath error:nil];

    // Since Xcode 11, XCTest.framework load XCTAutomationSupport.framework use LC_LOAD_DYLIB, so
    // we need to make sure XCTAutomationSupport.framework is available at @rpath when we load test bundle.
    if ([FBXcodeConfiguration.xcodeVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"11.0"]]) {
      NSString *XCTAutomationSupportFrameworkPath =
      [[FBXcodeConfiguration.developerDirectory
        stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform"]
        stringByAppendingPathComponent:@"Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework"];

      [FBListTestConfiguration copyFrameworkToApplicationAtPath:_runnerAppPath frameworkPath:XCTAutomationSupportFrameworkPath error:nil];
    }

    FBBundleDescriptor *appBundle = [FBBundleDescriptor bundleFromPath:_runnerAppPath error:nil];
    return [FBXCTestProcess
      startWithLaunchPath:appBundle.binary.path
      arguments:@[]
      environment:environment
      waitForDebugger:NO
      stdOutConsumer:stdOutConsumer
      stdErrConsumer:stdErrConsumer
      executor:executor
      timeout:self.testTimeout
      logger:logger];
  }

  NSString *xctestPath = executor.xctestPath;
  return [FBXCTestProcess
    startWithLaunchPath:xctestPath
    arguments:@[] // xctest needs no arguments as the shim will disregard & bypass them.
    environment:environment
    waitForDebugger:NO
    stdOutConsumer:stdOutConsumer
    stdErrConsumer:stdErrConsumer
    executor:executor
    timeout:self.testTimeout
    logger:logger];
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyListTestsOnly] = @YES;
  json[KeyRunnerAppPath] = _runnerAppPath ?: NSNull.null;
  return [json copy];
}

#pragma mark Private

+ (NSString *)copyFrameworkToApplicationAtPath:(NSString *)appPath frameworkPath:(NSString *)frameworkPath error:(NSError **)error
{
  if (![FBBundleDescriptor isApplicationAtPath:appPath]) {
    return nil;
  }

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSString *frameworksDir = [appPath stringByAppendingPathComponent:@"Frameworks"];
  BOOL isDirectory = NO;
  if ([fileManager fileExistsAtPath:frameworksDir isDirectory:&isDirectory]) {
    if (!isDirectory) {
      return [[FBControlCoreError
        describeFormat:@"%@ is not a directory", frameworksDir]
        fail:error];
    }
  } else {
    if (![fileManager createDirectoryAtPath:frameworksDir withIntermediateDirectories:NO attributes:nil error:error]) {
      return [[FBControlCoreError
        describeFormat:@"Create framework directory %@ failed", frameworksDir]
        fail:error];
    }
  }

  NSString *toPath = [frameworksDir stringByAppendingPathComponent:[frameworkPath lastPathComponent]];
  if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
    return appPath;
  }

  if (![fileManager copyItemAtPath:frameworkPath toPath:toPath error:error]) {
    return [[FBControlCoreError
      describeFormat:@"Error copying framework %@ to app %@.", frameworkPath, appPath]
      fail:error];
  }

  return appPath;
}

@end

@implementation FBTestManagerTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testTargetAppPath:(NSString *)testTargetAppPath testFilter:(NSString *)testFilter videoRecordingPath:(NSString *)videoRecordingPath testArtifactsFilenameGlobs:(nullable NSArray<NSString *> *)testArtifactsFilenameGlobs osLogPath:(nullable NSString *)osLogPath
{
  return [[FBTestManagerTestConfiguration alloc] initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testTargetAppPath:testTargetAppPath testFilter:testFilter videoRecordingPath:videoRecordingPath testArtifactsFilenameGlobs:testArtifactsFilenameGlobs osLogPath:osLogPath];
}

- (instancetype)initWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testTargetAppPath:(NSString *)testTargetAppPath testFilter:(NSString *)testFilter videoRecordingPath:(NSString *)videoRecordingPath testArtifactsFilenameGlobs:(NSArray<NSString *> *)testArtifactsFilenameGlobs osLogPath:(nullable NSString *)osLogPath
{
  self = [super initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
  if (!self) {
    return nil;
  }

  _runnerAppPath = runnerAppPath;
  _testTargetAppPath = testTargetAppPath;
  _testFilter = testFilter;
  _videoRecordingPath = videoRecordingPath;
  _testArtifactsFilenameGlobs = testArtifactsFilenameGlobs;
  _osLogPath = osLogPath;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return _testTargetAppPath != nil ? FBXCTestTypeUITest : FBXCTestTypeApplicationTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyRunnerAppPath] = self.runnerAppPath;
  json[KeyRunnerTargetPath] = self.testTargetAppPath;
  json[KeyTestFilter] = self.testFilter ?: NSNull.null;
  json[KeyVideoRecordingPath] = self.videoRecordingPath ?: NSNull.null;
  json[KeyTestArtifactsFilenameGlobs] = self.testArtifactsFilenameGlobs ?: NSNull.null;
  json[KeyOSLogPath] =  self.osLogPath ?: NSNull.null;
  return [json copy];
}

@end

@implementation FBLogicTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(NSString *)testFilter mirroring:(FBLogicTestMirrorLogs)mirroring
{
  return [[FBLogicTestConfiguration alloc] initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout testFilter:testFilter  mirroring:mirroring];
}

- (instancetype)initWithShims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(NSString *)testFilter mirroring:(FBLogicTestMirrorLogs)mirroring
{
  self = [super initWithShims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
  if (!self) {
    return nil;
  }

  _testFilter = testFilter;
  _mirroring = mirroring;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return FBXCTestTypeLogicTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyTestFilter] = self.testFilter ?: NSNull.null;
  return [json copy];
}

@end
