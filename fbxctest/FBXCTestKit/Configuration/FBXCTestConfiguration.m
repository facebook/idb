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

@interface FBXCTestConfiguration ()

@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) id<FBXCTestReporter> reporter;

@property (nonatomic, copy, readwrite) NSString *workingDirectory;
@property (nonatomic, copy, readwrite) NSString *testBundlePath;
@property (nonatomic, copy, readwrite) NSString *runnerAppPath;
@property (nonatomic, copy, readwrite) NSString *testFilter;

@property (nonatomic, copy, nullable, readwrite) FBXCTestShimConfiguration *shims;

@end

@implementation FBXCTestConfiguration

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger error:(NSError **)error
{
  return [self configurationFromArguments:arguments processUnderTestEnvironment:environment workingDirectory:workingDirectory reporter:reporter logger:logger timeout:0 error:nil];
}

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  Class configurationClass = [self testConfigurationClassForArguments:arguments error:error];
  if (!configurationClass) {
    return nil;
  }
  FBXCTestDestination *destination = [self destinationWithArguments:arguments error:error];
  if (!destination) {
    return nil;
  }

  FBXCTestConfiguration *configuration = [[configurationClass alloc] initWithDestination:destination reporter:reporter logger:logger processUnderTestEnvironment:environment timeout:timeout];
  if (![configuration loadWithArguments:arguments workingDirectory:workingDirectory error:error]) {
    return nil;
  }
  return configuration;
}

- (instancetype)initWithDestination:(FBXCTestDestination *)destination reporter:(nullable id<FBXCTestReporter>)reporter logger:(FBXCTestLogger *)logger processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment timeout:(NSTimeInterval)timeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _destination = destination;
  _reporter = reporter;
  _processUnderTestEnvironment = environment ?: @{};
  _logger = logger;
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

- (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments workingDirectory:(NSString *)workingDirectory error:(NSError **)error
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
    FBXCTestShimConfiguration *shimConfiguration = [FBXCTestShimConfiguration defaultShimConfigurationWithError:&innerError];
    if (!shimConfiguration) {
      return [FBXCTestError failBoolWithError:innerError errorOut:error];
    }
    self.shims = shimConfiguration;
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
    return [[FBXCTestDestinationiPhoneSimulator alloc] initWithDevice:nil version:nil];
  }
  // Extract the destination.
  id<FBControlCoreConfiguration_OS> os = nil;
  id<FBControlCoreConfiguration_Device> device = nil;
  if (![self parseSimulatorConfigurationFromDestination:destination osOut:&os deviceOut:&device error:error]) {
    return nil;
  }
  return [[FBXCTestDestinationiPhoneSimulator alloc] initWithDevice:device version:os];
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

+ (BOOL)parseSimulatorConfigurationFromDestination:(NSString *)destination osOut:(id<FBControlCoreConfiguration_OS> *)osOut deviceOut:(id<FBControlCoreConfiguration_Device> *)deviceOut error:(NSError **)error
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
      id<FBControlCoreConfiguration_Device> device = FBControlCoreConfigurationVariants.nameToDevice[value];
      if (!device) {
        return [[FBXCTestError
          describeFormat:@"Could not use a device named '%@'", value]
          failBool:error];
      }
      if (deviceOut) {
        *deviceOut = device;
      }
    } else if ([key isEqualToString:@"OS"]) {
      id<FBControlCoreConfiguration_OS> os = FBControlCoreConfigurationVariants.nameToOSVersion[value];
      if (!os) {
        return [[FBXCTestError
          describeFormat:@"Could not use a os named '%@'", value]
          failBool:error];
      }
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

- (BOOL)addTestBundle:(NSString *)testBundlePath runnerAppPath:(NSString *)runnerAppPath error:(NSError **)error
{
  if (_testBundlePath != nil) {
    return [[FBXCTestError describe:@"Only a single -logicTest or -appTest argument expected"] failBool:error];
  }
  _testBundlePath = testBundlePath;
  _runnerAppPath = runnerAppPath;
  return YES;
}

- (NSTimeInterval)defaultTimeout
{
  return 1000;
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
    if ([self.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]) {
      childKey = [@"SIMCTL_CHILD_" stringByAppendingString:childKey];
    }
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

@end

@implementation FBListTestConfiguration

- (NSString *)testType
{
  return @"logic-test";
}

@end

@implementation FBApplicationTestConfiguration

@dynamic runnerAppPath;

- (NSString *)testType
{
  return @"application-test";
}

@end

@implementation FBLogicTestConfiguration

@dynamic testFilter;

- (NSString *)testType
{
  return @"logic-test";
}

@end
