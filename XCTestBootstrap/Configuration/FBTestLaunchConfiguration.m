/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestLaunchConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestCommands.h"
#import "XCTestBootstrapError.h"

FBiOSTargetActionType const FBiOSTargetActionTypeTestLaunch = @"launch_xctest";

@implementation FBTestLaunchConfiguration

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostPath:(NSString *)testHostPath timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testBundlePath = testBundlePath;
  _applicationLaunchConfiguration = applicationLaunchConfiguration;
  _testHostPath = testHostPath;
  _timeout = timeout;
  _shouldInitializeUITesting = initializeUITesting;
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;

  return self;
}

+ (instancetype)configurationWithTestBundlePath:(NSString *)testBundlePath
{
  NSParameterAssert(testBundlePath);
  return [[FBTestLaunchConfiguration alloc] initWithTestBundlePath:testBundlePath applicationLaunchConfiguration:nil testHostPath:nil timeout:0 initializeUITesting:NO testsToRun:nil testsToSkip:[NSSet set]];
}

- (instancetype)withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip];
}

- (instancetype)withTestHostPath:(NSString *)testHostPath
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip];
}

- (instancetype)withTimeout:(NSTimeInterval)timeout
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip];
}

- (instancetype)withUITesting:(BOOL)shouldInitializeUITesting
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip];
}

- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:testsToRun
    testsToSkip:self.testsToSkip];
}

- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:testsToSkip];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBTestLaunchConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.testBundlePath == configuration.testBundlePath || [self.testBundlePath isEqualToString:configuration.testBundlePath]) &&
         (self.applicationLaunchConfiguration == configuration.applicationLaunchConfiguration  || [self.applicationLaunchConfiguration isEqual:configuration.applicationLaunchConfiguration]) &&
         (self.testHostPath == configuration.testHostPath || [self.testHostPath isEqualToString:configuration.testHostPath]) &&
         (self.testsToRun == configuration.testsToRun || [self.testsToRun isEqual:configuration.testsToRun]) &&
         (self.testsToSkip == configuration.testsToSkip || [self.testsToSkip isEqual:configuration.testsToSkip]) &&
         self.timeout == configuration.timeout &&
         self.shouldInitializeUITesting == configuration.shouldInitializeUITesting;
}

- (NSUInteger)hash
{
  return self.testBundlePath.hash ^ self.applicationLaunchConfiguration.hash ^ self.testHostPath.hash ^ (unsigned long) self.timeout ^ (unsigned long) self.shouldInitializeUITesting ^ self.testsToRun.hash ^ self.testsToSkip.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"FBTestLaunchConfiguration TestBundlePath %@ | AppConfig %@ | HostPath %@ | UITesting %d | TestsToRun %@ | TestsToSkip %@",
    self.testBundlePath,
    self.applicationLaunchConfiguration,
    self.testHostPath,
    self.shouldInitializeUITesting,
    self.testsToRun,
    self.testsToSkip
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

static NSString *const KeyAppLaunch = @"test_app_launch";
static NSString *const KeyBundlePath = @"test_bundle_path";
static NSString *const KeyHostPath = @"test_host_path";
static NSString *const KeyInitializeUITesting = @"ui_testing";
static NSString *const KeyTestsToRun = @"tests_to_run";
static NSString *const KeyTestsToSkip = @"tests_to_skip";
static NSString *const KeyTimeout = @"timeout";

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    KeyBundlePath : self.testBundlePath ?: NSNull.null,
    KeyAppLaunch : self.applicationLaunchConfiguration.jsonSerializableRepresentation ?: NSNull.null,
    KeyHostPath : self.testHostPath ?: NSNull.null,
    KeyTimeout : @(self.timeout),
    KeyInitializeUITesting : @(self.shouldInitializeUITesting),
    KeyTestsToRun : self.testsToRun.allObjects ?: NSNull.null,
    KeyTestsToSkip : self.testsToSkip.allObjects ?: NSNull.null
  };
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  NSString *bundlePath = [FBCollectionOperations nullableValueForDictionary:json key:KeyBundlePath];
  if (bundlePath && ![bundlePath isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String | Null for %@", bundlePath, KeyBundlePath]
      fail:error];
  }
  NSDictionary<NSString *, id> *appLaunchDictionary = [FBCollectionOperations nullableValueForDictionary:json key:KeyAppLaunch];
  FBApplicationLaunchConfiguration *appLaunch = nil;
  if (appLaunchDictionary) {
    appLaunch = [FBApplicationLaunchConfiguration inflateFromJSON:appLaunchDictionary error:error];
    if (!appLaunch) {
      return nil;
    }
  }
  NSString *testHostPath = [FBCollectionOperations nullableValueForDictionary:json key:KeyHostPath];
  if (testHostPath && ![testHostPath isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String | Null for %@", testHostPath, KeyHostPath]
      fail:error];
  }
  NSNumber *timeoutNumber = [FBCollectionOperations nullableValueForDictionary:json key:KeyTimeout];
  if (timeoutNumber && ![timeoutNumber isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number | Null for %@", timeoutNumber, KeyTimeout]
      fail:error];
  }
  NSTimeInterval timeout = timeoutNumber ? timeoutNumber.doubleValue : 0;
  NSNumber *initializeUITestingNumber = [FBCollectionOperations nullableValueForDictionary:json key:KeyInitializeUITesting];
  if (initializeUITestingNumber && ![initializeUITestingNumber isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number | Null for %@", initializeUITestingNumber, KeyInitializeUITesting]
      fail:error];
  }
  BOOL initializeUITesting = initializeUITestingNumber ? initializeUITestingNumber.boolValue : NO;
  NSArray<NSString *> *testsToRunArray = [FBCollectionOperations nullableValueForDictionary:json key:KeyTestsToRun];
  if (testsToRunArray && ![FBCollectionInformation isArrayHeterogeneous:testsToRunArray withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Array<String> | Null for %@", testsToRunArray, KeyTestsToRun]
      fail:error];
  }
  NSSet<NSString *> *testsToRun = testsToRunArray ? [NSSet setWithArray:testsToRunArray] : nil;
  NSArray<NSString *> *testsToSkipArray = [FBCollectionOperations nullableValueForDictionary:json key:KeyTestsToSkip];
  if (testsToRunArray && ![FBCollectionInformation isArrayHeterogeneous:testsToRunArray withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Array<String> | Null for %@", testsToSkipArray, KeyTestsToSkip]
      fail:error];
  }
  NSSet<NSString *> *testsToSkip = testsToSkipArray ? [NSSet setWithArray:testsToSkipArray] : nil;

  return [[self alloc]
    initWithTestBundlePath:bundlePath
    applicationLaunchConfiguration:appLaunch
    testHostPath:testHostPath
    timeout:timeout
    initializeUITesting:initializeUITesting
    testsToRun:testsToRun
    testsToSkip:testsToSkip];
}

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeTestLaunch;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  id<FBXCTestCommands> commands = (id<FBXCTestCommands> ) target;
  if (![commands conformsToProtocol:@protocol(FBXCTestCommands)]) {
    return [[FBXCTestError
      describeFormat:@"%@ does not conform to %@", target, NSStringFromProtocol(@protocol(FBXCTestCommands))]
      failBool:error];
  }

  id<FBXCTestOperation> operation = [commands startTestWithLaunchConfiguration:self error:error];
  if (!operation) {
    return NO;
  }
  if (self.timeout > 0) {
    if (![commands waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:self.timeout error:error]) {
      return NO;
    }
  }
  [delegate action:self target:target didGenerateTerminationHandle:operation];
  return YES;
}

@end
