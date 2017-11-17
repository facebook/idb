/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTestPreparationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"
#import "FBTestRunnerConfiguration.h"
#import "XCTestBootstrapError.h"

@interface FBSimulatorTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;
@property (nonatomic, strong, readonly) id<FBFileManager> fileManager;
@property (nonatomic, strong, readonly) id<FBCodesignProvider> codesign;

@end

@implementation FBSimulatorTestPreparationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                   workingDirectory:(NSString *)workingDirectory
{
  id<FBFileManager> fileManager = NSFileManager.defaultManager;
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  return [self strategyWithTestLaunchConfiguration:testLaunchConfiguration workingDirectory:workingDirectory fileManager:fileManager codesign:codesign];
}

+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                   workingDirectory:(NSString *)workingDirectory
                                        fileManager:(id<FBFileManager>)fileManager
                                           codesign:(id<FBCodesignProvider>)codesign
{
  return [[self alloc] initWithTestLaunchConfiguration:testLaunchConfiguration workingDirectory:workingDirectory fileManager:fileManager codesign:codesign];
}


- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                               workingDirectory:(NSString *)workingDirectory
                                    fileManager:(id<FBFileManager>)fileManager
                                       codesign:(id<FBCodesignProvider>)codesign
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testLaunchConfiguration = testLaunchConfiguration;
  _workingDirectory = workingDirectory;
  _fileManager = fileManager;
  _codesign = codesign;

  return self;
}

#pragma mark FBTestPreparationStrategy protocol

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget
{
  NSAssert(iosTarget, @"iosTarget is needed to load bundles");
  NSAssert(self.workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID, @"Test runner bundle ID is needed to load bundles");
  NSAssert(self.testLaunchConfiguration.testBundlePath, @"Path to test bundle is needed to load bundles");

  // Check the bundle is codesigned (if required).
  if (FBXcodeConfiguration.isXcode8OrGreater) {
    return [[[self.codesign
      cdHashForBundleAtPath:self.testLaunchConfiguration.testBundlePath]
      rephraseFailure:@"Could not determine bundle at path '%@' is codesigned and codesigning is required", self.testLaunchConfiguration.testBundlePath]
      onQueue:iosTarget.workQueue fmap:^(id _) {
        return [self prepareTestWithIOSTargetAfterCheckingCodesignature:iosTarget];
      }];
  }
  return [self prepareTestWithIOSTargetAfterCheckingCodesignature:iosTarget];
}

#pragma mark Private

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTargetAfterCheckingCodesignature:(id<FBiOSTarget>)iosTarget
{
  NSString *osRuntimePath = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/Developer"];
  NSString *developerLibraryPath = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library"];

  NSString *automationFrameworkPath = [osRuntimePath stringByAppendingPathComponent:@"Library/PrivateFrameworks/XCTAutomationSupport.framework"];
  NSString *xctTargetBootstrapInjectPath = [osRuntimePath stringByAppendingPathComponent:@"usr/lib/libXCTTargetBootstrapInject.dylib"];
  NSDictionary *testedApplicationAdditionalEnvironment = @{
    @"DYLD_INSERT_LIBRARIES" : xctTargetBootstrapInjectPath
  };
  if (![self.fileManager fileExistsAtPath:automationFrameworkPath] && ![self.fileManager fileExistsAtPath:xctTargetBootstrapInjectPath]) {
    automationFrameworkPath = nil;
    testedApplicationAdditionalEnvironment = nil;
  }

  // Prepare XCTest bundle
  NSError *error;
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle = [[[[[[[[[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.testLaunchConfiguration.testBundlePath]
    withUITesting:self.testLaunchConfiguration.shouldInitializeUITesting]
    withTestsToSkip:self.testLaunchConfiguration.testsToSkip]
    withTestsToRun:self.testLaunchConfiguration.testsToRun]
    withWorkingDirectory:self.workingDirectory]
    withSessionIdentifier:sessionIdentifier]
    withTargetApplicationPath:self.testLaunchConfiguration.targetApplicationPath]
    withTargetApplicationBundleID:self.testLaunchConfiguration.targetApplicationBundleID]
    withAutomationFrameworkPath:automationFrameworkPath]
    buildWithError:&error];
  if (!testBundle) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test bundle"]
      causedBy:error]
      failFuture];
  }

  // Prepare test runner
  FBProductBundle *application = [iosTarget.deviceOperator applicationBundleWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID error:&error];
  if (!application) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test runner"]
      causedBy:error]
      failFuture];
  }

  NSString *IDEBundleInjectionFrameworkPath = [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks/IDEBundleInjection.framework"];
  NSArray<NSString *> *XCTestFrameworksPaths = @[
    [developerLibraryPath stringByAppendingPathComponent:@"Frameworks"],
    [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks"],
  ];

  FBProductBundle *IDEBundleInjectionFramework = [[[FBProductBundleBuilder builder]
    withBundlePath:IDEBundleInjectionFrameworkPath]
    buildWithError:&error];
  if (!IDEBundleInjectionFramework) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare IDEBundleInjectionFramework"]
      causedBy:error]
      failFuture];
  }

  FBTestRunnerConfiguration *configuration = [FBTestRunnerConfiguration
    configurationWithSessionIdentifier:sessionIdentifier
    hostApplication:application
    ideInjectionFramework:IDEBundleInjectionFramework
    testBundle:testBundle
    testConfigurationPath:testBundle.configuration.path
    frameworkSearchPath:[XCTestFrameworksPaths componentsJoinedByString:@":"]
    testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
  return [FBFuture futureWithResult:configuration];
}

@end
