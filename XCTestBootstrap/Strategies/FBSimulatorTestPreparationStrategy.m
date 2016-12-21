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
#import "FBTestLaunchConfiguration.h"
#import "XCTestBootstrapError.h"


@interface FBSimulatorTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;
@property (nonatomic, strong, readonly) id<FBFileManager> fileManager;
@property (nonatomic, strong, readonly) id<FBCodesignProvider> codesign;

@end

@implementation FBSimulatorTestPreparationStrategy

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

#pragma mark - FBTestPreparationStrategy protocol

- (FBTestRunnerConfiguration *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget error:(NSError **)error
{
  NSAssert(iosTarget, @"iosTarget is needed to load bundles");
  NSAssert(self.workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID, @"Test runner bundle ID is needed to load bundles");
  NSAssert(self.testLaunchConfiguration.testBundlePath, @"Path to test bundle is needed to load bundles");

  // Check the bundle is codesigned (if required).
  NSError *innerError;
  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater && ![self.codesign cdHashForBundleAtPath:self.testLaunchConfiguration.testBundlePath error:&innerError]) {
    return [[[XCTestBootstrapError
      describeFormat:@"Could not determine bundle at path '%@' is codesigned and codesigning is required", self.testLaunchConfiguration.testBundlePath]
      causedBy:innerError]
      fail:error];
  }

  // Prepare XCTest bundle
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle = [[[[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.testLaunchConfiguration.testBundlePath]
    withUITesting:self.testLaunchConfiguration.shouldInitializeUITesting]
    withWorkingDirectory:self.workingDirectory]
    withSessionIdentifier:sessionIdentifier]
    buildWithError:&innerError];
  if (!testBundle) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test bundle"]
      causedBy:innerError]
      fail:error];
  }

  // Prepare test runner
  FBProductBundle *application = [iosTarget.deviceOperator applicationBundleWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID error:error];
  if (!application) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test runner"]
      causedBy:innerError]
      fail:error];
  }

  NSString *IDEBundleInjectionFrameworkPath = [FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks/IDEBundleInjection.framework"];

  FBProductBundle *IDEBundleInjectionFramework = [[[FBProductBundleBuilder builder]
    withBundlePath:IDEBundleInjectionFrameworkPath]
    buildWithError:&innerError];
  if (!IDEBundleInjectionFramework) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare IDEBundleInjectionFramework"]
      causedBy:innerError]
      fail:error];
  }

  return [[[[[[[FBTestRunnerConfigurationBuilder builder]
    withSessionIdentifer:sessionIdentifier]
    withTestRunnerApplication:application]
    withIDEBundleInjectionFramework:IDEBundleInjectionFramework]
    withWebDriverAgentTestBundle:testBundle]
    withTestConfigurationPath:testBundle.configuration.path]
    build];
}

@end
