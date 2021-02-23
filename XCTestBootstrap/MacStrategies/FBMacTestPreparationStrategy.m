/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBMacTestPreparationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBTestConfiguration.h"
#import "FBTestRunnerConfiguration.h"
#import "XCTestBootstrapError.h"

@interface FBMacTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;
@property (nonatomic, copy, readonly) FBXCTestShimConfiguration *shims;
@property (nonatomic, strong, readonly) NSFileManager *fileManager;
@property (nonatomic, strong, readonly) FBCodesignProvider *codesign;

@end

@implementation FBMacTestPreparationStrategy

- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration shims:(FBXCTestShimConfiguration *)shims workingDirectory:(NSString *)workingDirectory codesign:(FBCodesignProvider *)codesign
{
  NSAssert(workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(testLaunchConfiguration.applicationLaunchConfiguration.bundleID, @"Test runner bundle ID is needed to load bundles");
  NSAssert(testLaunchConfiguration.testBundlePath, @"Path to test bundle is needed to load bundles");

  self = [super init];
  if (!self) {
    return nil;
  }

  _testLaunchConfiguration = testLaunchConfiguration;
  _shims = shims;
  _workingDirectory = workingDirectory;
  _codesign = codesign;

  return self;
}

#pragma mark - FBTestPreparationStrategy protocol

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget
{
  NSAssert(iosTarget, @"iosTarget is needed to load bundles");
  return [self prepareTestWithIOSTargetAfterCheckingCodesignature:iosTarget];
}

#pragma mark Private

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTargetAfterCheckingCodesignature:(id<FBiOSTarget>)iosTarget
{
  // Paths
  NSString *developerPath = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/MacOSX.platform/Developer"];
  NSString *developerLibraryPath = [developerPath stringByAppendingPathComponent:@"Library"];
  NSString *developerFrameworksPath = [developerLibraryPath stringByAppendingPathComponent:@"Frameworks"];
  NSString *automationFrameworkPath = [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks/XCTAutomationSupport.framework"];
  NSArray<NSString *> *XCTestFrameworksPaths = @[
    [developerLibraryPath stringByAppendingPathComponent:@"Frameworks"],
    [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks"],
    developerFrameworksPath,
  ];
  NSString *xctTargetBootstrapInjectPath = [developerPath stringByAppendingPathComponent:@"usr/lib/libXCTTargetBootstrapInject.dylib"];

  // Environments
  NSDictionary *testedApplicationAdditionalEnvironment = @{
    @"DYLD_INSERT_LIBRARIES" : xctTargetBootstrapInjectPath
  };
  if (![self.fileManager fileExistsAtPath:automationFrameworkPath] && ![self.fileManager fileExistsAtPath:xctTargetBootstrapInjectPath]) {
    automationFrameworkPath = nil;
    testedApplicationAdditionalEnvironment = nil;
  }
  NSArray<NSString *> *injects = @[
    self.shims.macOSTestShimPath,
  ];
  NSDictionary<NSString *, NSString *> *hostApplicationAdditionalEnvironment = @{
    @"SHIMULATOR_START_XCTEST": @"1",
    @"DYLD_INSERT_LIBRARIES": [injects componentsJoinedByString:@":"],
  };

  // Prepare XCTest bundle
  NSError *error;
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBBundleDescriptor *testBundle = [FBBundleDescriptor bundleFromPath:self.testLaunchConfiguration.testBundlePath error:&error];
  if (!testBundle) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test bundle"]
      causedBy:error]
      failFuture];
  }

  FBTestConfiguration *testConfiguration = [FBTestConfiguration
    configurationByWritingToFileWithSessionIdentifier:sessionIdentifier
    moduleName:testBundle.name
    testBundlePath:testBundle.path
    uiTesting:self.testLaunchConfiguration.shouldInitializeUITesting
    testsToRun:self.testLaunchConfiguration.testsToRun
    testsToSkip:self.testLaunchConfiguration.testsToSkip
    targetApplicationPath:self.testLaunchConfiguration.targetApplicationPath
    targetApplicationBundleID:self.testLaunchConfiguration.targetApplicationBundleID
    automationFrameworkPath:automationFrameworkPath
    reportActivities:NO
    error:&error];
  if (!testBundle) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test configuration"]
      causedBy:error]
      failFuture];
  }

  // Prepare test runner
  return [[iosTarget
    installedApplicationWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID]
    onQueue:iosTarget.workQueue map:^(FBInstalledApplication *hostApplication) {
      return [FBTestRunnerConfiguration
        configurationWithSessionIdentifier:sessionIdentifier
        hostApplication:hostApplication.bundle
        hostApplicationAdditionalEnvironment:hostApplicationAdditionalEnvironment
        testBundle:testBundle
        testConfigurationPath:testConfiguration.path
        frameworkSearchPath:[XCTestFrameworksPaths componentsJoinedByString:@":"]
        testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
    }];
}

@end
