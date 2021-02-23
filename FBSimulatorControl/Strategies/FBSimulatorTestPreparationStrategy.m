/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorTestPreparationStrategy.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator.h"

@interface FBSimulatorTestPreparationStrategy ()

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;
@property (nonatomic, copy, readonly) FBXCTestShimConfiguration *shims;
@property (nonatomic, strong, readonly) id<FBFileManager> fileManager;
@property (nonatomic, strong, readonly) FBCodesignProvider *codesign;

@end

@implementation FBSimulatorTestPreparationStrategy

#pragma mark Initializers

- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration shims:(FBXCTestShimConfiguration *)shims workingDirectory:(NSString *)workingDirectory fileManager:(id<FBFileManager>)fileManager codesign:(FBCodesignProvider *)codesign
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
  _fileManager = fileManager;
  _codesign = codesign;

  return self;
}

#pragma mark FBTestPreparationStrategy protocol

- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(FBSimulator *)simulator
{
  NSParameterAssert([simulator isKindOfClass:FBSimulator.class]);

  // Check the bundle is codesigned (if required).
  if (FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid) {
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
  // Paths
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
    reportActivities:self.testLaunchConfiguration.reportActivities
    error:&error];
  if (!testBundle) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test configuration"]
      causedBy:error]
      failFuture];
  }

  FBXCTestShimConfiguration *shims = self.shims;

  return [[simulator
    installedApplicationWithBundleID:self.testLaunchConfiguration.applicationLaunchConfiguration.bundleID]
    onQueue:simulator.workQueue map:^(FBInstalledApplication *installedApplication) {
      NSMutableDictionary<NSString *, NSString *> *hostApplicationAdditionalEnvironment = [NSMutableDictionary dictionary];
      hostApplicationAdditionalEnvironment[@"SHIMULATOR_START_XCTEST"] = @"1";
      hostApplicationAdditionalEnvironment[@"DYLD_INSERT_LIBRARIES"] = shims.iOSSimulatorTestShimPath;
      if (self.testLaunchConfiguration.coveragePath) {
        hostApplicationAdditionalEnvironment[@"LLVM_PROFILE_FILE"] = self.testLaunchConfiguration.coveragePath;
      }
      // These Search Paths are added via "DYLD_FALLBACK_FRAMEWORK_PATH" so that they can be resolved when linked by the Application.
      // This is needed so that the Application is aware of how to link the XCTest.framework from the developer directory.
      // The Application binary will not contain linker opcodes that point to the XCTest.framework within the Simulator runtime bundle.
      // Therefore we need to provide them to the test runner so it can pass them to the app launch.
      NSArray<NSString *> *frameworkSearchPaths = [XCTestFrameworksPaths arrayByAddingObject:[installedApplication.bundle.path stringByAppendingPathComponent:@"Frameworks"]];
      return [FBTestRunnerConfiguration
        configurationWithSessionIdentifier:sessionIdentifier
        hostApplication:installedApplication.bundle
        hostApplicationAdditionalEnvironment:hostApplicationAdditionalEnvironment.copy
        testBundle:testBundle
        testConfigurationPath:testConfiguration.path
        frameworkSearchPath:[frameworkSearchPaths componentsJoinedByString:@":"]
        testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
    }];
}

@end
