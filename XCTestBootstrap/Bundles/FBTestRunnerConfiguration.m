/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestRunnerConfiguration.h"

#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"

@implementation FBTestRunnerConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier hostApplication:(FBProductBundle *)hostApplication hostApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)hostApplicationAdditionalEnvironment testBundle:(FBTestBundle *)testBundle testConfigurationPath:(NSString *)testConfigurationPath frameworkSearchPath:(NSString *)frameworkSearchPath testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  NSParameterAssert(sessionIdentifier);
  NSParameterAssert(hostApplication);
  NSParameterAssert(testConfigurationPath);
  NSParameterAssert(testBundle);

  NSArray<NSString *> *launchArguments = [self launchArguments];
  NSDictionary<NSString *, NSString *> *launchEnvironment = [self
                                                             launchEnvironmentWithHostApplication:hostApplication
                                                             hostApplicationAdditionalEnvironment:hostApplicationAdditionalEnvironment
                                                             testBundle:testBundle
                                                             testConfigurationPath:testConfigurationPath
                                                             frameworkSearchPath:frameworkSearchPath];
  return [[self alloc] initWithSessionIdentifier:sessionIdentifier testRunner:hostApplication launchArguments:launchArguments launchEnvironment:launchEnvironment testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
}

- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier testRunner:(FBProductBundle *)testRunner launchArguments:(NSArray<NSString *> *)launchArguments launchEnvironment:(NSDictionary<NSString *, NSString *> *)launchEnvironment testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sessionIdentifier = sessionIdentifier;
  _testRunner = testRunner;
  _launchArguments = launchArguments;
  _launchEnvironment = launchEnvironment;
  _testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark Private

+ (NSArray<NSString *> *)launchArguments
{
  return @[
    @"-NSTreatUnknownArgumentsAsOpen", @"NO",
    @"-ApplePersistenceIgnoreState", @"YES"
  ];
}

+ (NSDictionary *)launchEnvironmentWithHostApplication:(FBProductBundle *)hostApplication hostApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)hostApplicationAdditionalEnvironment testBundle:(FBTestBundle *)testBundle testConfigurationPath:(NSString *)testConfigurationPath frameworkSearchPath:(NSString *)frameworkSearchPath
{
  NSString *appFrameworks = [hostApplication.path stringByAppendingPathComponent:@"Frameworks"];
  NSMutableDictionary *environmentVariables = hostApplicationAdditionalEnvironment.mutableCopy;
  [environmentVariables addEntriesFromDictionary:@{
    @"AppTargetLocation" : hostApplication.binaryPath,
    @"DYLD_FRAMEWORK_PATH" : appFrameworks ?: @"",
    @"DYLD_LIBRARY_PATH" : appFrameworks ?: @"",
    @"DYLD_FALLBACK_FRAMEWORK_PATH" : frameworkSearchPath ?: @"",
    @"DYLD_FALLBACK_LIBRARY_PATH" : frameworkSearchPath ?: @"",
    @"OBJC_DISABLE_GC" : @"YES",
    @"TestBundleLocation" : testBundle.path,
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : testConfigurationPath,
  }];
  return [self addAdditionalEnvironmentVariables:environmentVariables.copy];
}

+ (NSDictionary *)addAdditionalEnvironmentVariables:(NSDictionary *)currentEnvironmentVariables
{
  NSString *prefix = @"CUSTOM_";
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self BEGINSWITH %@", prefix];
  NSArray *filter = [[NSProcessInfo.processInfo.environment allKeys] filteredArrayUsingPredicate:predicate];
  NSDictionary *envVariableWtihPrefix = [NSProcessInfo.processInfo.environment dictionaryWithValuesForKeys:filter];

  NSMutableDictionary *envs = [currentEnvironmentVariables mutableCopy];
  for (NSString *key in envVariableWtihPrefix)
  {
    envs[[key substringFromIndex:[prefix length]]] = envVariableWtihPrefix[key];
  }

  return [NSDictionary dictionaryWithDictionary:envs];
}

@end
