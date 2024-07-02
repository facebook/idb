/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConfiguration.h"
#import "FBCodeCoverageConfiguration.h"
#import "FBXCTestProcess.h"
#import "XCTestBootstrapError.h"

FBXCTestType const FBXCTestTypeApplicationTest = FBXCTestTypeApplicationTestValue;
FBXCTestType const FBXCTestTypeLogicTest = @"logic-test";
FBXCTestType const FBXCTestTypeListTest = @"list-test";
FBXCTestType const FBXCTestTypeUITest = @"ui-test";

@implementation FBXCTestConfiguration

#pragma mark Initializers

- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

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
  // TSAN is known to slow down all tests from running, bump the default test timeout to 1800s (instead of 500s).
#if __has_feature(thread_sanitizer) || defined(__SANITIZE_THREAD__)
  return 1800.0;
#endif
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
  NSData *data = [NSJSONSerialization dataWithJSONObject:self.jsonSerializableRepresentation options:0 error:NULL];
  NSParameterAssert(data);
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)isEqual:(FBXCTestConfiguration *)object
{
  // Class must match exactly in the class-cluster
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return (self.processUnderTestEnvironment == object.processUnderTestEnvironment || [self.processUnderTestEnvironment isEqualToDictionary:object.processUnderTestEnvironment])
      && (self.workingDirectory == object.workingDirectory || [self.workingDirectory isEqualToString:object.workingDirectory])
      && (self.testBundlePath == object.testBundlePath || [self.testBundlePath isEqualToString:object.testBundlePath])
      && (self.testType == object.testType || [self.testType isEqualToString:object.testType])
      && (self.waitForDebugger == object.waitForDebugger)
      && (self.testTimeout == object.testTimeout);
}

- (NSUInteger)hash
{
  return self.processUnderTestEnvironment.hash ^ self.workingDirectory.hash ^ self.testBundlePath.hash ^ self.testType.hash ^ ((NSUInteger) self.waitForDebugger) ^ ((NSUInteger) self.testTimeout);
}

#pragma mark JSON

static NSString *const KeyEnvironment = @"environment";
static NSString *const KeyListTestsOnly = @"list_only";
static NSString *const KeyOSLogPath = @"os_log_path";
static NSString *const KeyRunnerAppPath = @"test_host_path";
static NSString *const KeyRunnerTargetPath = @"test_target_path";
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

@implementation FBListTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath runnerAppPath:(nullable NSString *)runnerAppPath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout architectures:(nonnull NSSet<NSString *> *)architectures
{
  return [[FBListTestConfiguration alloc] initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath runnerAppPath:runnerAppPath waitForDebugger:waitForDebugger timeout:timeout architectures:architectures];
}

- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath runnerAppPath:(nullable NSString *)runnerAppPath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout architectures:(nonnull NSSet<NSString *> *)architectures
{
  self = [super initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
  if (!self) {
    return nil;
  }

  _runnerAppPath = runnerAppPath;
  _architectures = architectures;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return FBXCTestTypeListTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyListTestsOnly] = @YES;
  json[KeyRunnerAppPath] = _runnerAppPath ?: NSNull.null;
  return [json copy];
}

@end

@implementation FBTestManagerTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testTargetAppPath:(NSString *)testTargetAppPath testFilter:(NSString *)testFilter videoRecordingPath:(NSString *)videoRecordingPath testArtifactsFilenameGlobs:(nullable NSArray<NSString *> *)testArtifactsFilenameGlobs osLogPath:(nullable NSString *)osLogPath
{
  return [[FBTestManagerTestConfiguration alloc] initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testTargetAppPath:testTargetAppPath testFilter:testFilter videoRecordingPath:videoRecordingPath testArtifactsFilenameGlobs:testArtifactsFilenameGlobs osLogPath:osLogPath];
}

- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testTargetAppPath:(NSString *)testTargetAppPath testFilter:(NSString *)testFilter videoRecordingPath:(NSString *)videoRecordingPath testArtifactsFilenameGlobs:(NSArray<NSString *> *)testArtifactsFilenameGlobs osLogPath:(nullable NSString *)osLogPath
{
  self = [super initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
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

+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(NSString *)testFilter mirroring:(FBLogicTestMirrorLogs)mirroring coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration binaryPath:(nullable NSString *)binaryPath logDirectoryPath:(NSString *)logDirectoryPath architectures:(nonnull NSSet<NSString *> *)architectures
{
  return [[FBLogicTestConfiguration alloc] initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout testFilter:testFilter  mirroring:mirroring coverageConfiguration:coverageConfiguration binaryPath:binaryPath logDirectoryPath:logDirectoryPath architectures:architectures];
}

- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(NSString *)testFilter mirroring:(FBLogicTestMirrorLogs)mirroring coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration binaryPath:(nullable NSString *)binaryPath logDirectoryPath:(NSString *)logDirectoryPath architectures:(nonnull NSSet<NSString *> *)architectures
{
  self = [super initWithEnvironment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout];
  if (!self) {
    return nil;
  }

  _testFilter = testFilter;
  _mirroring = mirroring;
  _coverageConfiguration = coverageConfiguration;
  _binaryPath = binaryPath;
  _logDirectoryPath = logDirectoryPath;
  _architectures = architectures;

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
