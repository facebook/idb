/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestConfiguration.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBJSONTestReporter.h"
#import "FBXCTestError.h"
#import "FBXCTestLogger.h"
#import "FBXCTestDestination.h"
#import "FBXCTestShimConfiguration.h"

@implementation FBXCTestConfiguration

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory error:(NSError **)error
{
  return [self configurationFromArguments:arguments processUnderTestEnvironment:environment workingDirectory:workingDirectory timeout:0 error:nil];
}

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  Class configurationClass = [self testConfigurationClassForArguments:arguments error:error];
  if (!configurationClass) {
    return nil;
  }
  FBXCTestDestination *destination = [self destinationWithArguments:arguments error:error];
  if (!destination) {
    return nil;
  }
  FBXCTestShimConfiguration *shims = nil;
  NSString *testBundlePath = nil;
  NSString *runnerAppPath = nil;
  NSString *testFilter = nil;
  BOOL waitForDebugger = NO;

  if (![FBXCTestConfiguration loadWithArguments:arguments shimsOut:&shims testBundlePathOut:&testBundlePath runnerAppPathOut:&runnerAppPath testFilterOut:&testFilter waitForDebuggerOut:&waitForDebugger error:error]) {
    return nil;
  }
  return [[configurationClass alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:testFilter];
}

- (instancetype)initWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testFilter:(NSString *)testFilter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _destination = destination;
  _shims = shims;
  _processUnderTestEnvironment = environment ?: @{};
  _workingDirectory = workingDirectory;
  _testBundlePath = testBundlePath;
  _waitForDebugger = waitForDebugger;
  _testTimeout = timeout > 0 ? timeout : [self defaultTimeout];

  return self;
}

+ (Class)testConfigurationClassForArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  NSSet<NSString *> *argumentSet = [NSSet setWithArray:arguments];
  if ([argumentSet containsObject:@"-listTestsOnly"]) {
    return [FBListTestConfiguration class];
  }
  if ([argumentSet containsObject:@"-logicTest"]) {
    return [FBLogicTestConfiguration class];
  }
  if ([argumentSet containsObject:@"-appTest"]) {
    return [FBApplicationTestConfiguration class];
  }
  return [[FBControlCoreError
    describeFormat:@"Could not determine test runner type from %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
    fail:error];
}

+ (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments shimsOut:(FBXCTestShimConfiguration **)shimsOut testBundlePathOut:(NSString **)testBundlePathOut runnerAppPathOut:(NSString **)runnerAppPathOut testFilterOut:(NSString **)testFilterOut waitForDebuggerOut:(BOOL *)waitForDebuggerOut error:(NSError **)error
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
      NSString *testRunnerAppPath = [testRunnerPath stringByDeletingLastPathComponent];

      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = testBundlePath;
      *runnerAppPathOut = testRunnerAppPath;
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
    FBXCTestShimConfiguration *shimConfiguration = [FBXCTestShimConfiguration defaultShimConfigurationWithError:&innerError];
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

#pragma mark Helpers

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

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestConfiguration *)object
{
  // Class must match exactly in the class-cluster
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return (self.destination == object.destination || [self.destination isEqual:object.destination])
      && (self.shims == object.shims || [self.shims isEqual:object.shims])
      && (self.processUnderTestEnvironment == object.processUnderTestEnvironment || [self.processUnderTestEnvironment isEqualToDictionary:object.processUnderTestEnvironment])
      && (self.workingDirectory == object.workingDirectory || [self.workingDirectory isEqualToString:object.workingDirectory])
      && (self.testBundlePath == object.testBundlePath || [self.testBundlePath isEqualToString:object.testBundlePath])
      && (self.testType == object.testType || [self.testType isEqualToString:object.testType])
      && (self.waitForDebugger == object.waitForDebugger)
      && (self.testTimeout == object.testTimeout);
}

- (NSUInteger)hash
{
  return self.destination.hash ^ self.shims.hash ^ self.processUnderTestEnvironment.hash ^ self.workingDirectory.hash ^ self.testBundlePath.hash ^ self.testType.hash ^ ((NSUInteger) self.waitForDebugger) ^ ((NSUInteger) self.testTimeout);
}

#pragma mark JSON

NSString *const KeyDestination = @"destination";
NSString *const KeyEnvironment = @"environment";
NSString *const KeyListTestsOnly = @"list_only";
NSString *const KeyRunnerAppPath = @"test_host_path";
NSString *const KeyShims = @"shims";
NSString *const KeyTestBundlePath = @"test_bundle_path";
NSString *const KeyTestFilter = @"test_filter";
NSString *const KeyTestTimeout = @"test_timeout";
NSString *const KeyTestType = @"test_type";
NSString *const KeyWaitForDebugger = @"wait_for_debugger";
NSString *const KeyWorkingDirectory = @"working_directory";

NSString *const ValueLogicTest = @"logic-test";
NSString *const ValueApplicationTest = @"application-test";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyDestination: self.destination.jsonSerializableRepresentation,
    KeyShims: self.shims.jsonSerializableRepresentation ?: NSNull.null,
    KeyEnvironment: self.processUnderTestEnvironment,
    KeyWorkingDirectory: self.workingDirectory,
    KeyTestBundlePath: self.testBundlePath,
    KeyTestType: self.testType,
    KeyListTestsOnly: @NO,
    KeyWaitForDebugger: @(self.waitForDebugger),
    KeyTestTimeout: @(self.testTimeout),
  };
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  NSString *testType = json[KeyTestType];
  if (![testType isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", testType, KeyTestType]
      fail:error];
  }
  NSNumber *listTestsOnly = json[KeyListTestsOnly] ?: @NO;
  if (![listTestsOnly isKindOfClass:NSNumber.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Number for %@", listTestsOnly, KeyListTestsOnly]
      fail:error];
  }
  NSDictionary<NSString *, NSString *> *environment = json[KeyEnvironment];
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictionary<String, String> for %@", environment, KeyEnvironment]
      fail:error];
  }
  NSString *workingDirectory = json[KeyWorkingDirectory];
  if (![workingDirectory isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", workingDirectory, KeyWorkingDirectory]
      fail:error];
  }
  NSString *testBundlePath = json[KeyTestBundlePath];
  if (![testBundlePath isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", testBundlePath, KeyTestBundlePath]
      fail:error];
  }
  NSNumber *waitForDebugger = [FBCollectionOperations nullableValueForDictionary:json key:KeyWaitForDebugger] ?: @NO;
  if (![waitForDebugger isKindOfClass:NSNumber.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Number for %@", waitForDebugger, KeyWaitForDebugger]
      fail:error];
  }
  NSNumber *testTimeout = [FBCollectionOperations nullableValueForDictionary:json key:KeyTestTimeout] ?: @0;
  if (![testTimeout isKindOfClass:NSNumber.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Number for %@", testTimeout, KeyTestTimeout]
      fail:error];
  }
  NSDictionary<NSString *, id> *destinationDictionary = json[KeyDestination];
  if (![FBCollectionInformation isDictionaryHeterogeneous:destinationDictionary keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictonary<String, String> for %@", destinationDictionary, KeyDestination]
      fail:error];
  }
  FBXCTestDestination *destination = [FBXCTestDestination inflateFromJSON:destinationDictionary error:error];
  if (!destination) {
    return nil;
  }
  NSDictionary<NSString *, id> *shimsDictionary = [FBCollectionOperations nullableValueForDictionary:json key:KeyShims];
  if (shimsDictionary && ![FBCollectionInformation isDictionaryHeterogeneous:shimsDictionary keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictonary<String, String> for %@", shimsDictionary, KeyShims]
      fail:error];
  }
  FBXCTestShimConfiguration *shims = nil;
  if (shimsDictionary) {
    shims = [FBXCTestShimConfiguration inflateFromJSON:shimsDictionary error:error];
    if (!shims) {
      return nil;
    }
  }
  Class clusterClass = nil;
  if ([testType isEqualToString:ValueLogicTest]) {
    clusterClass = listTestsOnly.boolValue ? FBListTestConfiguration.class : FBLogicTestConfiguration.class;
  } else if ([testType isEqualToString:ValueApplicationTest]) {
    clusterClass = FBApplicationTestConfiguration.class;
  } else {
    return [[FBControlCoreError
      describeFormat:@"Test Type %@ is not a value Test Type for %@", testType, KeyTestType]
      fail:error];
  }
  return [clusterClass
    inflateFromJSON:json
    destination:destination
    shims:shims
    environment:environment
    workingDirectory:workingDirectory
    testBundlePath:testBundlePath
    waitForDebugger:waitForDebugger.boolValue
    timeout:testTimeout.doubleValue
    error:nil];
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json destination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [[self alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:nil testFilter:nil];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end

@implementation FBListTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout
{
  return [[FBListTestConfiguration alloc] initWithDestination:destination shims:nil environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:nil testFilter:nil];
}

#pragma mark Public

- (NSString *)testType
{
  return ValueLogicTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyListTestsOnly] = @YES;
  return [json copy];
}

@end

@implementation FBApplicationTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath
{
  return [[FBApplicationTestConfiguration alloc] initWithDestination:destination shims:nil environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:nil];
}

- (instancetype)initWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testFilter:(NSString *)testFilter
{
  self = [super initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:testFilter];
  if (!self) {
    return nil;
  }

  _runnerAppPath = runnerAppPath;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return ValueApplicationTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyRunnerAppPath] = self.runnerAppPath;
  return [json copy];
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json destination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  NSString *runnerAppPath = json[KeyRunnerAppPath];
  if (![runnerAppPath isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", runnerAppPath, KeyRunnerAppPath]
      fail:error];
  }
  return [[FBApplicationTestConfiguration alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:nil];
}

@end

@implementation FBLogicTestConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(NSString *)testFilter
{
  return [[FBLogicTestConfiguration alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:nil testFilter:testFilter];
}

- (instancetype)initWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testFilter:(NSString *)testFilter
{
  self = [super initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:testFilter];
  if (!self) {
    return nil;
  }

  _testFilter = testFilter;

  return self;
}

#pragma mark Public

- (NSString *)testType
{
  return ValueLogicTest;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = [NSMutableDictionary dictionaryWithDictionary:[super jsonSerializableRepresentation]];
  json[KeyTestFilter] = self.testFilter ?: NSNull.null;
  return [json copy];
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json destination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  NSString *keyTestFilter = [FBCollectionOperations nullableValueForDictionary:json key:KeyTestFilter];
  if (keyTestFilter && ![keyTestFilter isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", keyTestFilter, KeyTestFilter]
      fail:error];
  }
  return [[FBLogicTestConfiguration alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:nil testFilter:keyTestFilter];
}

@end
