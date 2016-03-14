/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestRunnerConfiguration.h"

#import "FBApplicationDataPackage.h"
#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"

@interface FBTestRunnerConfiguration ()
@property (nonatomic, copy) NSUUID *sessionIdentifier;
@property (nonatomic, strong) FBProductBundle *testRunner;
@property (nonatomic, copy) NSArray *launchArguments;
@property (nonatomic, copy) NSDictionary *launchEnvironment;
@end

@implementation FBTestRunnerConfiguration
@end


@interface FBTestRunnerConfigurationBuilder ()
@property (nonatomic, copy) NSUUID *sessionIdentifier;
@property (nonatomic, copy) NSString *testConfigurationPath;
@property (nonatomic, copy) NSString *frameworkSearchPath;
@property (nonatomic, strong) FBProductBundle *testRunner;
@property (nonatomic, strong) FBProductBundle *IDEBundleInjectionFramework;
@property (nonatomic, strong) FBTestBundle *webDriverAgentTestBundle;
@end

@implementation FBTestRunnerConfigurationBuilder

+ (instancetype)builder
{
  return [self.class new];
}

- (instancetype)withTestRunnerApplication:(FBProductBundle *)testRunnerApplication
{
  self.testRunner = testRunnerApplication;
  return self;
}

- (instancetype)withTestConfigurationPath:(NSString *)testConfigurationPath
{
  self.testConfigurationPath = testConfigurationPath;
  return self;
}


- (instancetype)withFrameworkSearchPath:(NSString *)frameworkSearchPath
{
  self.frameworkSearchPath = frameworkSearchPath;
  return self;
}

- (instancetype)withSessionIdentifer:(NSUUID *)sessionIdentifier
{
  self.sessionIdentifier = sessionIdentifier;
  return self;
}

- (instancetype)withIDEBundleInjectionFramework:(FBProductBundle *)IDEBundleInjectionFramework
{
  self.IDEBundleInjectionFramework = IDEBundleInjectionFramework;
  return self;
}

- (instancetype)withWebDriverAgentTestBundle:(FBTestBundle *)webDriverAgentTestBundle
{
  self.webDriverAgentTestBundle = webDriverAgentTestBundle;
  return self;
}

- (FBTestRunnerConfiguration *)build
{
  NSAssert(self.sessionIdentifier, @"sessionIdentifier is required to create data package");
  NSAssert(self.testRunner, @"testRunnerApplication is required to create data package");
  NSAssert(self.testConfigurationPath, @"testConfigurationPath is required to create data package");
  NSAssert(self.IDEBundleInjectionFramework, @"IDEBundleInjectionFramework is required to create data package");
  NSAssert(self.webDriverAgentTestBundle, @"webDriverAgentTestBundle is required to create data package");

  FBTestRunnerConfiguration *config = [FBTestRunnerConfiguration new];
  config.sessionIdentifier = self.sessionIdentifier;
  config.testRunner = self.testRunner;
  config.launchArguments = [self buildAttributes];
  config.launchEnvironment = [self buildEnvironment];
  return config;
}

- (NSArray *)buildAttributes
{
  return
  @[
    @"-NSTreatUnknownArgumentsAsOpen", @"NO",
    @"-ApplePersistenceIgnoreState", @"YES"
  ];
}

- (NSDictionary *)buildEnvironment
{
  return
  @{
    @"AppTargetLocation" : self.testRunner.binaryPath,
    @"DYLD_INSERT_LIBRARIES" : self.IDEBundleInjectionFramework.binaryPath,
    @"DYLD_FRAMEWORK_PATH" : self.frameworkSearchPath ?: @"",
    @"DYLD_LIBRARY_PATH" : self.frameworkSearchPath ?: @"",
    @"OBJC_DISABLE_GC" : @"YES",
    @"TestBundleLocation" : self.webDriverAgentTestBundle.path,
    @"XCInjectBundle" : self.webDriverAgentTestBundle.path,
    @"XCInjectBundleInto" : self.testRunner.binaryPath,
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : self.testConfigurationPath,
  };
}

@end
