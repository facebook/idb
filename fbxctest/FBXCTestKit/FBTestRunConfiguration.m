/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestRunConfiguration.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBJSONTestReporter.h"
#import "FBXCTestError.h"
#import "FBXCTestLogger.h"

static NSString *const iOSXCTestShimFileName = @"otest-shim-ios.dylib";
static NSString *const MacXCTestShimFileName = @"otest-shim-osx.dylib";
static NSString *const MacQueryShimFileName = @"otest-query-lib-osx.dylib";

@interface FBTestRunConfiguration ()
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readwrite) FBSimulatorConfiguration *targetDeviceConfiguration;

@property (nonatomic, copy, readwrite) NSString *workingDirectory;
@property (nonatomic, copy, readwrite) NSString *testBundlePath;
@property (nonatomic, copy, readwrite) NSString *runnerAppPath;
@property (nonatomic, copy, readwrite) NSString *simulatorName;
@property (nonatomic, copy, readwrite) NSString *simulatorOS;
@property (nonatomic, copy, readwrite) NSString *testFilter;
@property (nonatomic, copy, readwrite) NSString *shimDirectory;

@property (nonatomic, assign, readwrite) BOOL runWithoutSimulator;
@property (nonatomic, assign, readwrite) BOOL listTestsOnly;

@end

@implementation FBTestRunConfiguration

- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;
  _processUnderTestEnvironment = environment ?: @{};

  return self;
}

- (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments workingDirectory:(NSString *)workingDirectory error:(NSError **)error
{
  // Sets the default logger for all Frameworks.
  self.logger = [FBXCTestLogger loggerInTemporaryDirectory];
  [FBControlCoreGlobalConfiguration setDefaultLogger:self.logger];

  arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];
  NSUInteger nextArgument = 0;
  NSString *testFilter = nil;
  BOOL shimsRequired = YES;

  while (nextArgument < arguments.count) {
    NSString *argument = arguments[nextArgument++];
    if ([argument isEqualToString:@"run-tests"]) {
      // Ignore. This is the only action we support.
      continue;
    } else if ([argument isEqualToString:@"-listTestsOnly"]) {
      self.listTestsOnly = YES;
      continue;
    }
    if (nextArgument >= arguments.count) {
      return [[FBXCTestError describeFormat:@"The last option is missing a parameter: %@", argument] failBool:error];
    }
    NSString *parameter = arguments[nextArgument++];
    if ([argument isEqualToString:@"-reporter"]) {
      if (![self checkReporter:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-sdk"]) {
      if (![self setSDK:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-destination"]) {
      if (![self setDestination:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-logicTest"]) {
      [self addTestBundle:parameter runnerAppPath:nil error:error];
    } else if ([argument isEqualToString:@"-appTest"]) {
      NSRange colonRange = [parameter rangeOfString:@":"];
      if (colonRange.length == 0) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain a colon: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = [parameter substringToIndex:colonRange.location];
      NSString *testRunnerPath = [parameter substringFromIndex:colonRange.location + 1];
      NSString *testRunnerAppPath = [testRunnerPath stringByDeletingLastPathComponent];
      [self addTestBundle:testBundlePath runnerAppPath:testRunnerAppPath error:error];
      shimsRequired = NO;
    } else if ([argument isEqualToString:@"-only"]) {
      if (testFilter != nil) {
        return [[FBXCTestError describeFormat:@"Multiple -only options specified: %@, %@", testFilter, parameter] failBool:error];
      }
      testFilter = parameter;
    } else {
      return [[FBXCTestError describeFormat:@"Unrecognized option: %@", argument] failBool:error];
    }
  }

  if (shimsRequired) {
    NSError *innerError = nil;
    NSString *shimDirectory = [FBTestRunConfiguration findShimDirectoryWithError:&innerError];
    if (!shimDirectory) {
      return [FBXCTestError failBoolWithError:innerError errorOut:error];
    }
    self.shimDirectory = shimDirectory;
  }
  if (!self.reporter) {
    self.reporter = [[FBJSONTestReporter new] initWithTestBundlePath:_testBundlePath testType:self.testType];
  }
  if (testFilter != nil) {
    NSString *expectedPrefix = [self.testBundlePath stringByAppendingString:@":"];
    if (![testFilter hasPrefix:expectedPrefix]) {
      return [[FBXCTestError describeFormat:@"Test filter '%@' does not apply to the test bundle '%@'", testFilter, self.testBundlePath] failBool:error];
    }
    self.testFilter = [testFilter substringFromIndex:expectedPrefix.length];
  }
  if (!self.reporter) {
    self.reporter = [[FBJSONTestReporter new] initWithTestBundlePath:_testBundlePath testType:self.testType];
  }

  FBSimulatorConfiguration *simulatorConfiguration = [FBSimulatorConfiguration defaultConfiguration];
  if (_simulatorName) {
    simulatorConfiguration = [simulatorConfiguration withDeviceNamed:_simulatorName];
  }
  if (_simulatorOS) {
    simulatorConfiguration = [simulatorConfiguration withOSNamed:_simulatorOS];
  }
  self.targetDeviceConfiguration = simulatorConfiguration;
  self.workingDirectory = workingDirectory;
  return YES;
}

- (BOOL)checkReporter:(NSString *)reporter error:(NSError **)error
{
  if (![reporter isEqualToString:@"json-stream"]) {
    return [[FBXCTestError describeFormat:@"Unsupported reporter: %@", reporter] failBool:error];
  }
  return YES;
}

- (BOOL)setSDK:(NSString *)sdk error:(NSError **)error
{
  if ([sdk isEqualToString:@"iphonesimulator"]) {
    self.runWithoutSimulator = NO;
    return YES;
  }
  if ([sdk isEqualToString:@"macosx"]) {
    self.runWithoutSimulator = YES;
    return YES;
  }
  return [[FBXCTestError describeFormat:@"Unsupported SDK: %@", sdk] failBool:error];
}

- (BOOL)setDestination:(NSString *)destination error:(NSError **)error
{
  NSArray<NSString *> *parts = [destination componentsSeparatedByString:@","];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSRange equalsRange = [part rangeOfString:@"="];
    if (equalsRange.length == 0) {
      return [[FBXCTestError describeFormat:@"Destination specifier should contain '=': %@", part] failBool:error];
    }
    NSString *key = [part substringToIndex:equalsRange.location];
    NSString *value = [part substringFromIndex:equalsRange.location + 1];
    if ([key isEqualToString:@"name"]) {
      if (![self setSimulatorName:value error:error]) {
        return NO;
      }
    } else if ([key isEqualToString:@"OS"]) {
      if (![self setSimulatorOS:value error:error]) {
        return NO;
      }
    } else {
      return [[FBXCTestError describeFormat:@"Unrecognized destination specifier: %@", key] failBool:error];
    }
  }
  return YES;
}

- (BOOL)setSimulatorName:(NSString *)name error:(NSError **)error
{
  if (_simulatorName) {
    return [[FBXCTestError describeFormat:@"Multiple destination simulator names specified: %@ and %@", _simulatorName, name] failBool:error];
  }
  _simulatorName = name;
  return YES;
}

- (BOOL)setSimulatorOS:(NSString *)os error:(NSError **)error
{
  if (_simulatorOS) {
    return [[FBXCTestError describeFormat:@"Multiple destination simulator OS specified: %@ and %@", _simulatorOS, os] failBool:error];
  }
  _simulatorOS = os;
  return YES;
}

- (BOOL)addTestBundle:(NSString *)testBundlePath runnerAppPath:(NSString *)runnerAppPath error:(NSError **)error
{
  if (_testBundlePath != nil) {
    return [[FBXCTestError describe:@"Only a single -logicTest or -appTest argument expected"] failBool:error];
  }
  _testBundlePath = testBundlePath;
  _runnerAppPath = runnerAppPath;
  return YES;
}

- (NSString *)testType
{
  if (_runnerAppPath) {
    return @"application-test";
  } else {
    return @"logic-test";
  }
}

#pragma mark Shim File Paths

- (NSString *)iOSSimulatorOtestShimPath
{
  return [self.shimDirectory stringByAppendingPathComponent:iOSXCTestShimFileName];
}

- (NSString *)macOtestShimPath
{
  return [self.shimDirectory stringByAppendingPathComponent:MacXCTestShimFileName];
}

- (NSString *)macOtestQueryPath
{
  return [self.shimDirectory stringByAppendingPathComponent:MacQueryShimFileName];
}

+ (NSString *)fbxctestInstallationRoot
{
  NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
  if (!executablePath.isAbsolutePath) {
    executablePath = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingString:executablePath];
  }
  executablePath = [executablePath stringByStandardizingPath];
  NSString *path = [[executablePath
    stringByDeletingLastPathComponent]
    stringByDeletingLastPathComponent];
  return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}

+ (NSString *)findShimDirectoryWithError:(NSError **)error
{
  // If an environment variable is provided, use it
  NSString *environmentDefinedDirectory = NSProcessInfo.processInfo.environment[@"TEST_SHIMS_DIRECTORY"];
  if (environmentDefinedDirectory) {
    return [self confirmExistenceOfRequiredShimsInDirectory:environmentDefinedDirectory withError:error];
  }

  // Otherwise, expect it to be relative to the location of the current executable.
  NSString *libPath = [[self fbxctestInstallationRoot] stringByAppendingPathComponent:@"lib"];
  return [self confirmExistenceOfRequiredShimsInDirectory:libPath withError:error];
}

+ (NSString *)confirmExistenceOfRequiredShimsInDirectory:(NSString *)directory withError:(NSError **)error
{
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBXCTestError
      describeFormat:@"A shim directory was expected at '%@', but it was not there", directory]
      fail:error];
  }

  NSDictionary<NSString *, NSNumber *> *shims = @{
    iOSXCTestShimFileName : FBControlCoreGlobalConfiguration.isXcode8OrGreater ? @YES : @NO,
    MacXCTestShimFileName : @NO,
    MacQueryShimFileName : @NO,
  };

  id<FBCodesignProvider> codesign = FBCodeSignCommand.codeSignCommandWithAdHocIdentity;
  for (NSString *filename in shims) {
    NSString *shimPath = [directory stringByAppendingPathComponent:iOSXCTestShimFileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:shimPath]) {
      return [[FBXCTestError
        describeFormat:@"The iOS xctest Simulator Shim was expected at the location '%@', but it was not there", shimPath]
        fail:error];
    }
    if (!shims[filename].boolValue) {
      continue;
    }
    NSError *innerError = nil;
    if (![codesign cdHashForBundleAtPath:shimPath error:&innerError]) {
      return [[[FBXCTestError
        describeFormat:@"Shim at path %@ was required to be signed, but it was not", shimPath]
        causedBy:innerError]
        fail:error];
    }
  }
  return directory;
}

- (NSString *)xctestPathForSimulator:(nullable FBSimulator *)simulator
{
  if (simulator == nil) {
    return [FBControlCoreGlobalConfiguration.developerDirectory
      stringByAppendingPathComponent:@"usr/bin/xctest"];
  } else {
    return [FBControlCoreGlobalConfiguration.developerDirectory
      stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"];
  }
}

+ (NSDictionary<NSString *, NSString *> *)buildEnvironmentWithEntries:(NSDictionary<NSString *, NSString *> *)entries simulator:(nullable FBSimulator *)simulator
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
    if (simulator) {
      childKey = [@"SIMCTL_CHILD_" stringByAppendingString:childKey];
    }
    environment[childKey] = environmentOverrides[key];
  }
  return environment.copy;
}

@end
