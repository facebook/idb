/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

/* Portions Copyright © Microsoft Corporation. */

#import "FBTestRunnerConfiguration.h"

#import "FBApplicationDataPackage.h"
#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"

@implementation FBTestRunnerConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier hostApplication:(FBProductBundle *)hostApplication ideInjectionFramework:(FBProductBundle *)ideInjectionFramework testBundle:(FBTestBundle *)testBundle testConfigurationPath:(NSString *)testConfigurationPath frameworkSearchPath:(NSString *)frameworkSearchPath
{
  NSParameterAssert(sessionIdentifier);
  NSParameterAssert(hostApplication);
  NSParameterAssert(testConfigurationPath);
  NSParameterAssert(ideInjectionFramework);
  NSParameterAssert(testBundle);

  NSArray<NSString *> *launchArguments = [self launchArguments];
  NSDictionary<NSString *, NSString *> *launchEnvironment = [self
    launchEnvironmentWithHostApplication:hostApplication
    ideInjectionFramework:ideInjectionFramework
    testBundle:testBundle
    testConfigurationPath:testConfigurationPath
    frameworkSearchPath:frameworkSearchPath];

  return [[self alloc] initWithSessionIdentifier:sessionIdentifier testRunner:hostApplication launchArguments:launchArguments launchEnvironment:launchEnvironment];
}

- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier testRunner:(FBProductBundle *)testRunner launchArguments:(NSArray<NSString *> *)launchArguments launchEnvironment:(NSDictionary<NSString *, NSString *> *)launchEnvironment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sessionIdentifier = sessionIdentifier;
  _testRunner = testRunner;
  _launchArguments = launchArguments;
  _launchEnvironment = launchEnvironment;

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

+ (NSDictionary *)launchEnvironmentWithHostApplication:(FBProductBundle *)hostApplication ideInjectionFramework:(FBProductBundle *)ideInjectionFramework testBundle:(FBTestBundle *)testBundle testConfigurationPath:(NSString *)testConfigurationPath frameworkSearchPath:(NSString *)frameworkSearchPath
{
  return @{
    @"AppTargetLocation" : hostApplication.binaryPath,
    @"DYLD_INSERT_LIBRARIES" : ideInjectionFramework.binaryPath,
    @"DYLD_FRAMEWORK_PATH" : frameworkSearchPath ?: @"",
    @"DYLD_LIBRARY_PATH" : frameworkSearchPath ?: @"",
    @"OBJC_DISABLE_GC" : @"YES",
    @"TestBundleLocation" : testBundle.path,
    @"XCInjectBundle" : testBundle.path,
    @"XCInjectBundleInto" : hostApplication.binaryPath,
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : testConfigurationPath,
  };
}

@end
