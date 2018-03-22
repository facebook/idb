/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestCommandLine.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestDestination.h"
#import "FBXCTestKeyboardSimulatorConfigurator.h"
#import "FBXCTestWatchdogConfigurator.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeFBXCTest = @"fbxctest";

NSString *const FBVideoRecordingPathArgName = @"-video";
NSString *const FBOsLogPathArgName = @"-oslog";
NSString *const FBTestLogPathArgName = @"-testlog";
NSString *const FBSimulatorLocalizationSettingsArgName = @"-simulator-localization-settings";
NSString *const FBWatchdogSettingsArgName = @"-watchdog-settings";

@implementation FBXCTestCommandLine

#pragma mark Initializers

+ (instancetype)commandLineWithConfiguration:(FBXCTestConfiguration *)configuration
                                 destination:(FBXCTestDestination *)destination
                      simulatorConfigurators:(NSArray<id<FBXCTestSimulatorConfigurator>> *)simulatorConfigurators
                  simulatorManagementOptions:(FBSimulatorManagementOptions)simulatorManagementOptions
{
    return [[self alloc]
            initWithConfiguration:configuration
            destination:destination
            simulatorConfigurators:simulatorConfigurators
            simulatorManagementOptions:simulatorManagementOptions];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration
                          destination:(FBXCTestDestination *)destination
               simulatorConfigurators:(NSArray<id<FBXCTestSimulatorConfigurator>> *)simulatorConfigurators
           simulatorManagementOptions:(FBSimulatorManagementOptions)simulatorManagementOptions
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _destination = destination;
  _simulatorConfigurators = [NSArray arrayWithArray:simulatorConfigurators];
  _simulatorManagementOptions = simulatorManagementOptions;

  return self;
}

#pragma mark Parsing

+ (nullable instancetype)commandLineFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  FBXCTestDestination *destination = [self destinationWithArguments:arguments error:error];
  if (!destination) {
    return nil;
  }
  FBXCTestShimConfiguration *shims = nil;
  NSString *testBundlePath = nil;
  NSString *runnerAppPath = nil;
  NSArray<NSString *> *testFilters = nil;
  NSString *testTargetPathOut = nil;
  NSArray<NSString *> *additionalApplicationPathsOut = nil;
  NSArray<id<FBXCTestSimulatorConfigurator>> *simulatorConfigurators = nil;
  BOOL waitForDebugger = NO;
  NSString *videoRecordingPath = nil;
  NSString *osLogPath = nil;
  NSString *testLogPath = nil;
  FBSimulatorManagementOptions simulatorManagementOptions = FBSimulatorManagementOptionsKillAllOnFirstStart;
  
  if (![FBXCTestCommandLine loadWithArguments:arguments logger:logger shimsOut:&shims testBundlePathOut:&testBundlePath runnerAppPathOut:&runnerAppPath testTargetPathOut:&testTargetPathOut additionalApplicationPathsOut:&additionalApplicationPathsOut testFilterOut:&testFilters waitForDebuggerOut:&waitForDebugger simulatorConfigurators:&simulatorConfigurators simulatorManagementOptions:&simulatorManagementOptions videoRecordingPath:&videoRecordingPath oslogPath:&osLogPath testLogPath:&testLogPath error:error]) {
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
      testFilters:testFilters
      mirroring:FBLogicTestMirrorFileLogs];
  } else if ([argumentSet containsObject:@"-appTest"]) {
    NSMutableDictionary<NSString *, NSString *> *allEnvironment = [NSProcessInfo.processInfo.environment mutableCopy];
    [allEnvironment addEntriesFromDictionary:environment];

    videoRecordingPath = allEnvironment[@"FBXCTEST_VIDEO_RECORDING_PATH"];
    NSString *testArtifactsFilenameGlob = allEnvironment[@"FBXCTEST_TEST_ARTIFACTS_FILENAME_GLOB"];
    NSArray<NSString *> *testArtifactsFilenameGlobs = testArtifactsFilenameGlob != nil ? @[testArtifactsFilenameGlob] : nil;
    osLogPath = allEnvironment[@"FBXCTEST_OS_LOG_PATH"];

    configuration = [FBTestManagerTestConfiguration
      configurationWithShims:shims
      environment:environment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:waitForDebugger
      timeout:timeout
      runnerAppPath:runnerAppPath
      testTargetAppPath:testTargetPathOut
      testFilters:testFilters
      videoRecordingPath:videoRecordingPath
      testArtifactsFilenameGlobs:testArtifactsFilenameGlobs
      osLogPath:osLogPath
      additionalApplicationPaths:@[]
      runnerAppLogPath:testLogPath
      applicationLogPath:testLogPath];
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
      testFilters:testFilters
      videoRecordingPath:videoRecordingPath
      testArtifactsFilenameGlobs:nil
      osLogPath:osLogPath
      additionalApplicationPaths:additionalApplicationPathsOut
      runnerAppLogPath:testLogPath
      applicationLogPath:testLogPath];
  }
  if (!configuration) {
    return [[FBControlCoreError
      describeFormat:@"Could not determine test runner type from %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
      fail:error];
  }
  return [[FBXCTestCommandLine alloc]
          initWithConfiguration:configuration
          destination:destination
          simulatorConfigurators:simulatorConfigurators
          simulatorManagementOptions:simulatorManagementOptions];
}

+ (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments logger:(id<FBControlCoreLogger>)logger shimsOut:(FBXCTestShimConfiguration **)shimsOut testBundlePathOut:(NSString **)testBundlePathOut runnerAppPathOut:(NSString **)runnerAppPathOut testTargetPathOut:(NSString **)testTargetPathOut additionalApplicationPathsOut:(NSArray<NSString *> **)additionalApplicationPathsOut testFilterOut:(NSArray<NSString *> **)testFiltersOut waitForDebuggerOut:(BOOL *)waitForDebuggerOut simulatorConfigurators:(NSArray<id<FBXCTestSimulatorConfigurator>> **)simulatorConfiguratorsOut simulatorManagementOptions:(out FBSimulatorManagementOptions *)simulatorManagementOptions videoRecordingPath:(out NSString **)videoRecordingPath oslogPath:(out NSString **)oslogPath testLogPath:(out NSString **)testLogPath error:(NSError **)error
{
  NSUInteger nextArgument = 0;
  NSMutableArray<NSString *> *testFilters = [[NSMutableArray alloc] init];
  NSMutableArray<id<FBXCTestSimulatorConfigurator>> *configurators = [[NSMutableArray alloc] init];
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
    } else if ([argument isEqualToString:@"-keep-simulators-alive"]) {
      *simulatorManagementOptions = 0;
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
    }  else if ([argument isEqualToString:@"-workingDirectory"]) {
      // Ignore. This is handled by the bootstrapper itself.
      continue;
    } else if ([argument isEqualToString:@"-timeout"]) {
      // Ignore. This is handled by the bootstrapper itself.
      continue;
    } else if ([argument isEqualToString:FBVideoRecordingPathArgName]) {
      *videoRecordingPath = parameter;
    } else if ([argument isEqualToString:FBOsLogPathArgName]) {
      *oslogPath = parameter;
    } else if ([argument isEqualToString:FBTestLogPathArgName]) {
      *testLogPath = parameter;
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
      if (components.count < 3) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain three or more colon separated components: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = components[0];
      NSString *testRunnerPath = [self extractBundlePathFromString:components[1]];
      NSString *testTargetPath = [self extractBundlePathFromString:components[2]];
      NSMutableArray *additionalApplicationPaths = [NSMutableArray new];
      for (NSUInteger componentId = 3; componentId < components.count; componentId++) {
        [additionalApplicationPaths addObject:components[componentId]];
      }

      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = testBundlePath;
      *runnerAppPathOut = testRunnerPath;
      *testTargetPathOut = testTargetPath;
      *additionalApplicationPathsOut = [additionalApplicationPaths copy];
    } else if ([argument isEqualToString:@"-only"]) {
      [testFilters addObject:parameter];
    } else if ([argument isEqualToString:FBSimulatorLocalizationSettingsArgName] ||
               [argument isEqualToString:FBWatchdogSettingsArgName]) {
      id<FBXCTestSimulatorConfigurator> configurator = nil;
      if ([self configuratorForArgument:argument parameter:parameter logger:logger outConfigurator:&configurator error:error] && configurator != nil) {
        [configurators addObject:configurator];
      } else {
        return [[FBXCTestError describeFormat:@"Option %@ has wrong argument %@", argument, parameter] failBool:error];
      }
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
  if (testFilters.count > 0) {
    NSString *expectedPrefix = [*testBundlePathOut stringByAppendingString:@":"];
    NSMutableArray *mappedFilters = [[NSMutableArray alloc] init];
    for (NSString *testFilter in testFilters) {
      if (![testFilter hasPrefix:expectedPrefix]) {
        return [[FBXCTestError
                 describeFormat:@"Test filter '%@' does not apply to the test bundle '%@'", testFilter, *testBundlePathOut]
                failBool:error];
      }
      [mappedFilters addObject:[testFilter substringFromIndex:expectedPrefix.length]];
    }
    *testFiltersOut = [mappedFilters copy];
  }
  
  *simulatorConfiguratorsOut = [configurators copy];

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

+ (BOOL)configuratorForArgument:(NSString *)argument parameter:(NSString *)parameter logger:(id<FBControlCoreLogger>)logger outConfigurator:(out id<FBXCTestSimulatorConfigurator> *)outConfigurator error:(NSError **)error
{
  if ([argument isEqualToString:FBSimulatorLocalizationSettingsArgName] ||
      [argument isEqualToString:FBWatchdogSettingsArgName]) {
    NSData *contents = [NSData dataWithContentsOfFile:parameter options:NSDataReadingMappedAlways error:error];
    if (contents == nil) { return NO; }
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:contents options:0 error:error];
    if ([dictionary isKindOfClass:NSDictionary.class]) {
      if ([argument isEqualToString:FBSimulatorLocalizationSettingsArgName]) {
        *outConfigurator = [FBXCTestKeyboardSimulatorConfigurator configurationFromDictionary:dictionary logger:logger];
      } else if ([argument isEqualToString:FBWatchdogSettingsArgName]) {
        *outConfigurator = [FBXCTestWatchdogConfigurator configurationFromDictionary:dictionary logger:logger];
      }
      return YES;
    }
  }
  return NO;
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
