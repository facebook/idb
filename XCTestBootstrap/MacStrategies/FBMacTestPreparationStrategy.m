/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBMacTestPreparationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"
#import "FBTestRunnerConfiguration.h"
#import "XCTestBootstrapError.h"
#import "FBXCTestShimConfiguration.h"

@interface FBMacTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;
@property (nonatomic, copy, readonly) FBXCTestShimConfiguration *shims;
@property (nonatomic, strong, readonly) id<FBFileManager> fileManager;
@property (nonatomic, strong, readonly) id<FBCodesignProvider> codesign;

@end

@implementation FBMacTestPreparationStrategy

+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                   workingDirectory:(NSString *)workingDirectory
{
  id<FBFileManager> fileManager = NSFileManager.defaultManager;
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  FBXCTestShimConfiguration *shims = [[FBXCTestShimConfiguration defaultShimConfiguration] await:nil];
  return [self strategyWithTestLaunchConfiguration:testLaunchConfiguration shims:shims workingDirectory:workingDirectory fileManager:fileManager codesign:codesign];
}


+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                              shims:(FBXCTestShimConfiguration *)shims
                                   workingDirectory:(NSString *)workingDirectory
                                        fileManager:(id<FBFileManager>)fileManager
                                           codesign:(id<FBCodesignProvider>)codesign
{
  return [[self alloc] initWithTestLaunchConfiguration:testLaunchConfiguration shims:shims workingDirectory:workingDirectory fileManager:fileManager codesign:codesign];
}


- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                          shims:(FBXCTestShimConfiguration *)shims
                               workingDirectory:(NSString *)workingDirectory
                                    fileManager:(id<FBFileManager>)fileManager
                                       codesign:(id<FBCodesignProvider>)codesign
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testLaunchConfiguration = testLaunchConfiguration;
  _shims = shims;
  _workingDirectory = workingDirectory;
  _fileManager = fileManager;
  _codesign = codesign;

  return self;
}

#pragma mark - FBTestPreparationStrategy protocol

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget
{
  NSAssert(iosTarget, @"iosTarget is needed to load bundles");
  NSAssert(self.workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID, @"Test runner bundle ID is needed to load bundles");
  NSAssert(self.testLaunchConfiguration.testBundlePath, @"Path to test bundle is needed to load bundles");

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
  return [[[iosTarget
    installedApplicationWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID]
    onQueue:iosTarget.workQueue fmap:^(FBInstalledApplication *installedApplication) {
      return [FBFuture resolveValue:^(NSError **innerError) {
        return [FBProductBundleBuilder productBundleFromInstalledApplication:installedApplication error:innerError];
      }];
    }]
    onQueue:iosTarget.workQueue map:^(FBProductBundle *hostApplication) {
      return [FBTestRunnerConfiguration
        configurationWithSessionIdentifier:sessionIdentifier
        hostApplication:hostApplication
        hostApplicationAdditionalEnvironment:hostApplicationAdditionalEnvironment
        testBundle:testBundle
        testConfigurationPath:testBundle.configuration.path
        frameworkSearchPath:[XCTestFrameworksPaths componentsJoinedByString:@":"]
        testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
    }];
}

@end
