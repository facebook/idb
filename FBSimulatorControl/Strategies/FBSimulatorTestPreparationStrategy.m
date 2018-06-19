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
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator.h"

@interface FBSimulatorTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBXCTestShimConfiguration *shims;
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

#pragma mark FBTestPreparationStrategy protocol

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(FBSimulator *)simulator
{
  NSParameterAssert([simulator isKindOfClass:FBSimulator.class]);
  NSAssert(self.workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID, @"Test runner bundle ID is needed to load bundles");
  NSAssert(self.testLaunchConfiguration.testBundlePath, @"Path to test bundle is needed to load bundles");

  // Check the bundle is codesigned (if required).
  if (FBXcodeConfiguration.isXcode8OrGreater && FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid) {
    return [[[self.codesign
      cdHashForBundleAtPath:self.testLaunchConfiguration.testBundlePath]
      rephraseFailure:@"Could not determine bundle at path '%@' is codesigned and codesigning is required", self.testLaunchConfiguration.testBundlePath]
      onQueue:simulator.workQueue fmap:^(id _) {
        return [self prepareTestWithIOSTargetAfterCheckingCodesignature:simulator];
      }];
  }
  return [self prepareTestWithIOSTargetAfterCheckingCodesignature:simulator];
}

#pragma mark Private

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTargetAfterCheckingCodesignature:(FBSimulator *)simulator
{
  NSString *platformDeveloperFrameworksPath = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks"];
  NSString *runtimeRoot = simulator.device.runtime.root;
  NSString *developerRuntimePath = [runtimeRoot stringByAppendingPathComponent:@"Developer"];
  NSString *developerLibraryPath = [developerRuntimePath stringByAppendingPathComponent:@"Library"];

  NSString *xctTargetBootstrapInjectPath = [developerRuntimePath stringByAppendingPathComponent:@"usr/lib/libXCTTargetBootstrapInject.dylib"];
  NSString *automationFrameworkPath = [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks/XCTAutomationSupport.framework"];
  NSArray<NSString *> *XCTestFrameworksPaths = @[
    [developerLibraryPath stringByAppendingPathComponent:@"Frameworks"],
    [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks"],
    platformDeveloperFrameworksPath,
  ];

  NSArray<NSString *> *injects = @[
    self.shims.iOSSimulatorTestShimPath,
   ];
  NSDictionary *hostApplicationAdditionalEnvironment = @{
    @"SHIMULATOR_START_XCTEST": @"1",
    @"DYLD_INSERT_LIBRARIES": [injects componentsJoinedByString:@":"],
  };

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
  FBProductBundle *application = [simulator.deviceOperator applicationBundleWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID error:&error];
  if (!application) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test runner"]
      causedBy:error]
      failFuture];
  }

  FBTestRunnerConfiguration *configuration = [FBTestRunnerConfiguration
    configurationWithSessionIdentifier:sessionIdentifier
    hostApplication:application
    hostApplicationAdditionalEnvironment:hostApplicationAdditionalEnvironment.copy
    testBundle:testBundle
    testConfigurationPath:testBundle.configuration.path
    frameworkSearchPath:[XCTestFrameworksPaths componentsJoinedByString:@":"]
    testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
  return [FBFuture futureWithResult:configuration];
}

@end
