/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestCommandLine.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestDestination.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeFBXCTest = @"fbxctest";

@implementation FBXCTestCommandLine

#pragma mark Initializers

+ (instancetype)commandLineWithConfiguration:(FBXCTestConfiguration *)configuration destination:(FBXCTestDestination *)destination
{
  return [[self alloc] initWithConfiguration:configuration destination:destination];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration destination:(FBXCTestDestination *)destination
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _destination = destination;

  return self;
}

#pragma mark Parsing

+ (nullable instancetype)commandLineFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory error:(NSError **)error
{
  return [self commandLineFromArguments:arguments processUnderTestEnvironment:environment workingDirectory:workingDirectory timeout:0 error:nil];
}

+ (nullable instancetype)commandLineFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  FBXCTestDestination *destination = [self destinationWithArguments:arguments error:error];
  if (!destination) {
    return nil;
  }
  FBXCTestShimConfiguration *shims = nil;
  NSString *testBundlePath = nil;
  NSString *runnerAppPath = nil;
  NSString *testFilter = nil;
  NSString *testTargetPathOut = nil;
  BOOL waitForDebugger = NO;
  if (![FBXCTestCommandLine loadWithArguments:arguments shimsOut:&shims testBundlePathOut:&testBundlePath runnerAppPathOut:&runnerAppPath testTargetPathOut:&testTargetPathOut testFilterOut:&testFilter waitForDebuggerOut:&waitForDebugger error:error]) {
    return nil;
  }
  NSSet<NSString *> *argumentSet = [NSSet setWithArray:arguments];
  FBXCTestConfiguration *configuration = nil;
  if ([argumentSet containsObject:@"-listTestsOnly"]) {
    if (![argumentSet containsObject:@"-appTest"]) {
      runnerAppPath = nil;
    }
    configuration = [FBListTestConfiguration
      configurationWithShims:shims
      environment:environment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      runnerAppPath:runnerAppPath
      waitForDebugger:waitForDebugger
      timeout:timeout];
  } else if ([argumentSet containsObject:@"-logicTest"]) {
    configuration = [FBLogicTestConfiguration
      configurationWithShims:shims
      environment:environment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:waitForDebugger
      timeout:timeout
      testFilter:testFilter
      mirroring:FBLogicTestMirrorFileLogs];
  } else if ([argumentSet containsObject:@"-appTest"]) {
    NSMutableDictionary<NSString *, NSString *> *allEnvironment = [NSProcessInfo.processInfo.environment mutableCopy];
    [allEnvironment addEntriesFromDictionary:environment];

    NSString *videoRecordingPath = allEnvironment[@"FBXCTEST_VIDEO_RECORDING_PATH"];
    NSString *testArtifactsFilenameGlob = allEnvironment[@"FBXCTEST_TEST_ARTIFACTS_FILENAME_GLOB"];
    NSArray<NSString *> *testArtifactsFilenameGlobs = testArtifactsFilenameGlob != nil ? @[testArtifactsFilenameGlob] : nil;
    NSString *osLogPath = allEnvironment[@"FBXCTEST_OS_LOG_PATH"];

    configuration = [FBTestManagerTestConfiguration
      configurationWithShims:shims
      environment:environment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:waitForDebugger
      timeout:timeout
      runnerAppPath:runnerAppPath
      testTargetAppPath:nil
      testFilter:testFilter
      videoRecordingPath:videoRecordingPath
      testArtifactsFilenameGlobs:testArtifactsFilenameGlobs
      osLogPath:osLogPath];
  } else if ([argumentSet containsObject:@"-uiTest"]) {
    configuration = [FBTestManagerTestConfiguration
      configurationWithShims:shims
      environment:environment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:waitForDebugger
      timeout:timeout
      runnerAppPath:runnerAppPath
      testTargetAppPath:testTargetPathOut
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil];
  }
  if (!configuration) {
    return [[FBControlCoreError
      describeFormat:@"Could not determine test runner type from %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
      fail:error];
  }
  return [[FBXCTestCommandLine alloc] initWithConfiguration:configuration destination:destination];
}

+ (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments shimsOut:(FBXCTestShimConfiguration **)shimsOut testBundlePathOut:(NSString **)testBundlePathOut runnerAppPathOut:(NSString **)runnerAppPathOut testTargetPathOut:(NSString **)testTargetPathOut testFilterOut:(NSString **)testFilterOut waitForDebuggerOut:(BOOL *)waitForDebuggerOut error:(NSError **)error
{
  NSUInteger nextArgument = 0;
  NSString *testFilter = nil;
  BOOL shimsRequired = YES;

  while (nextArgument < arguments.count) {
    NSString *argument = arguments[nextArgument++];
    if ([argument isEqualToString:@"run-tests"]) {
      // Ignore. This is the only action we support.
      continue;
    } else if ([argument isEqualToString:@"-listTestsOnly"]) {
      // Ignore. This is handled by the configuration class.
      continue;
    } else if ([argument isEqualToString:@"-waitForDebugger"]) {
      *waitForDebuggerOut = YES;
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
      // Ignore. This is handled when extracting the destination
    } else if ([argument isEqualToString:@"-destination"]) {
      // Ignore. This is handled when extracting the destination
    } else if ([argument isEqualToString:@"-logicTest"]) {
      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = parameter;
    } else if ([argument isEqualToString:@"-appTest"]) {
      NSRange colonRange = [parameter rangeOfString:@":"];
      if (colonRange.length == 0) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain a colon: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = [parameter substringToIndex:colonRange.location];
      NSString *testRunnerPath = [parameter substringFromIndex:colonRange.location + 1];
      NSString *testRunnerAppPath = [self extractBundlePathFromString:testRunnerPath];

      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = testBundlePath;
      *runnerAppPathOut = testRunnerAppPath;
    } else if ([argument isEqualToString:@"-uiTest"]) {
      NSArray *components = [parameter componentsSeparatedByString:@":"];
      if (components.count != 3) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain three colon separated components: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = components[0];
      NSString *testRunnerPath = [self extractBundlePathFromString:components[1]];
      NSString *testTargetPath = [self extractBundlePathFromString:components[2]];

      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = testBundlePath;
      *runnerAppPathOut = testRunnerPath;
      *testTargetPathOut = testTargetPath;
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
    FBXCTestShimConfiguration *shimConfiguration = [[FBXCTestShimConfiguration defaultShimConfiguration] await:&innerError];
    if (!shimConfiguration) {
      return [FBXCTestError failBoolWithError:innerError errorOut:error];
    }
    *shimsOut = shimConfiguration;
  }
  if (testFilter != nil) {
    NSString *expectedPrefix = [*testBundlePathOut stringByAppendingString:@":"];
    if (![testFilter hasPrefix:expectedPrefix]) {
      return [[FBXCTestError
        describeFormat:@"Test filter '%@' does not apply to the test bundle '%@'", testFilter, *testBundlePathOut]
        failBool:error];
    }
    *testFilterOut = [testFilter substringFromIndex:expectedPrefix.length];
  }

  return YES;
}

+ (BOOL)checkReporter:(NSString *)reporter error:(NSError **)error
{
  if (![reporter isEqualToString:@"json-stream"]) {
    return [[FBXCTestError describeFormat:@"Unsupported reporter: %@", reporter] failBool:error];
  }
  return YES;
}

+ (FBXCTestDestination *)destinationWithArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  NSOrderedSet<NSString *> *argumentSet = [NSOrderedSet orderedSetWithArray:arguments];
  NSMutableOrderedSet<NSString *> *subset = [NSMutableOrderedSet orderedSetWithArray:arguments];
  NSArray<NSString *> *macOSXSDKArguments = @[@"-sdk", @"macosx"];
  NSArray<NSString *> *iPhoneSimulatorSDKArguments = @[@"-sdk", @"iphonesimulator"];

  // Check for a macosx destination, return early and ignore -destination argument.
  [subset intersectOrderedSet:[NSOrderedSet orderedSetWithArray:macOSXSDKArguments]];
  if ([subset.array isEqualToArray:macOSXSDKArguments]) {
    return [FBXCTestDestinationMacOSX new];
  }

  // Check for an iPhoneSimulator Destination.
  subset = [NSMutableOrderedSet orderedSetWithArray:arguments];
  [subset intersectOrderedSet:[NSOrderedSet orderedSetWithArray:iPhoneSimulatorSDKArguments]];
  NSString *destination = [self destinationArgumentFromArguments:argumentSet];
  if (![subset.array isEqualToArray:iPhoneSimulatorSDKArguments] && !destination) {
    return [[FBXCTestError
      describeFormat:@"No valid SDK or Destination provided in %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
      fail:error];
  }
  // No Destination exists so return early.
  if (!destination) {
    return [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil];
  }
  // Extract the destination.
  FBOSVersionName os = nil;
  FBDeviceModel model = nil;
  if (![self parseSimulatorConfigurationFromDestination:destination osOut:&os modelOut:&model error:error]) {
    return nil;
  }
  return [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:model version:os];
}

+ (NSString *)destinationArgumentFromArguments:(NSOrderedSet<NSString *> *)arguments
{
  NSUInteger index = [arguments indexOfObject:@"-destination"];
  if (index == NSNotFound) {
    return nil;
  }
  index += 1;
  if (index >= arguments.count) {
    return nil;
  }
  return arguments[index];
}

+ (BOOL)parseSimulatorConfigurationFromDestination:(NSString *)destination osOut:(FBOSVersionName *)osOut modelOut:(FBDeviceModel *)modelOut error:(NSError **)error
{
  NSArray<NSString *> *parts = [destination componentsSeparatedByString:@","];

  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSRange equalsRange = [part rangeOfString:@"="];
    if (equalsRange.length == 0) {
      return [[FBXCTestError
        describeFormat:@"Destination specifier should contain '=': %@", part]
        failBool:error];
    }
    NSString *key = [part substringToIndex:equalsRange.location];
    NSString *value = [part substringFromIndex:equalsRange.location + 1];
    if ([key isEqualToString:@"name"]) {
      FBDeviceModel model = value;
      if (modelOut) {
        *modelOut = model;
      }
    } else if ([key isEqualToString:@"OS"]) {
      FBOSVersionName os = value;
      if (osOut) {
        *osOut = os;
      }
    } else {
      return [[FBXCTestError
        describeFormat:@"Unrecognized destination specifier: %@", key]
        failBool:error];
    }
  }
  return YES;
}

+ (NSString *)extractBundlePathFromString:(NSString *)path
{
  while (![path hasSuffix:@"app"] && path.length != 0) {
    path = path.stringByDeletingLastPathComponent;
  }
  return path;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestCommandLine *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [object.configuration isEqual:self.configuration] && [object.destination isEqual:self.destination];
}

- (NSUInteger)hash
{
  return self.configuration.hash ^ self.destination.hash;
}

#pragma mark Properties

static NSTimeInterval FetchTotalTestProportion = 0.8; // Fetching cannot take greater than 80% of the total test timeout.

- (NSTimeInterval)testPreparationTimeout
{
  return self.globalTimeout * FetchTotalTestProportion;
}

- (NSTimeInterval)globalTimeout
{
  return self.configuration.testTimeout;
}

@end
