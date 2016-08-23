/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceTestPreparationStrategy.h"

#import "FBApplicationDataPackage.h"
#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"
#import "FBTestRunnerConfiguration.h"
#import "NSFileManager+FBFileManager.h"
#import "FBCodeSignCommand.h"
#import "XCTestBootstrapError.h"

@interface FBDeviceTestPreparationStrategy ()
@property (nonatomic, copy) NSString *applicationPath;
@property (nonatomic, copy) NSString *applicationDataPath;
@property (nonatomic, copy) NSString *testBundlePath;
@property (nonatomic, strong) id<FBFileManager> fileManager;
@end

@implementation FBDeviceTestPreparationStrategy

+ (instancetype)strategyWithTestRunnerApplicationPath:(NSString *)applicationPath
                                  applicationDataPath:(NSString *)applicationDataPath
                                       testBundlePath:(NSString *)testBundlePath
                               pathToXcodePlatformDir:(NSString *)pathToXcodePlatformDir
                                     workingDirectory:(NSString *)workingDirectory
{
    NSLog(@"Creating %@ for %@", NSStringFromClass(self.class), @{
                                                                  @"applicationPath" : applicationPath,
                                                                  @"applicationDataPath" : applicationDataPath,
                                                                  @"testBundlePath" : testBundlePath,
                                                                  @"pathToXcodePlatformDir" : pathToXcodePlatformDir,
                                                                  @"workingDirectory" : workingDirectory
                                                                  });
  return
  [self strategyWithTestRunnerApplicationPath:applicationPath
                          applicationDataPath:applicationDataPath
                               testBundlePath:testBundlePath
                       pathToXcodePlatformDir:pathToXcodePlatformDir
                             workingDirectory:workingDirectory
                                  fileManager:[NSFileManager defaultManager]];
}

+ (instancetype)strategyWithTestRunnerApplicationPath:(NSString *)applicationPath
                                  applicationDataPath:(NSString *)applicationDataPath
                                       testBundlePath:(NSString *)testBundlePath
                               pathToXcodePlatformDir:(NSString *)pathToXcodePlatformDir
                                     workingDirectory:(NSString *)workingDirectory
                                          fileManager:(id<FBFileManager>)fileManager
{
    
    FBDeviceTestPreparationStrategy *strategy = [self.class new];
    strategy.applicationPath = applicationPath;
    strategy.applicationDataPath = applicationDataPath;
    strategy.testBundlePath = testBundlePath;
    strategy.fileManager = fileManager;
    strategy.pathToXcodePlatformDir = pathToXcodePlatformDir;
    strategy.workingDirectory = workingDirectory;
    NSLog(@"[%@ %@] => %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), strategy);
  return strategy;
}

- (FBTestRunnerConfiguration *)prepareTestWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator error:(NSError **)error
{
  NSAssert(deviceOperator, @"deviceOperator is needed to load bundles");
  NSAssert(self.applicationPath, @"Path to application is needed to load bundles");
  NSAssert(self.applicationDataPath, @"Path to application data bundle is needed to prepare bundles");
  NSAssert(self.testBundlePath, @"Path to test bundle is needed to load bundles");
    NSAssert(self.pathToXcodePlatformDir, @"Path to Xcode Platform Dir is needed to load test frameworks");

  NSError *innerError;
  // Load tested application
  FBProductBundle *testRunner =
  [[[[FBProductBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.applicationPath]
      withCodesignProvider:deviceOperator.codesignProvider]
   buildWithError:&innerError];
  if (!testRunner) {
    return
    [[[XCTestBootstrapError describe:@"Failed to prepare test runner app"]
      causedBy:innerError]
     fail:error];
  }

  if (![deviceOperator isApplicationInstalledWithBundleID:testRunner.bundleID error:&innerError]) {
    if (![deviceOperator installApplicationWithPath:testRunner.path error:&innerError]) {
      return
      [[[XCTestBootstrapError describe:@"Failed to install test runner app"]
        causedBy:innerError]
       fail:error];
    }
  }

  // Get tested app path on device
  NSString *remotePath = [deviceOperator applicationPathForApplicationWithBundleID:testRunner.bundleID error:&innerError];
  if (!remotePath) {
    return
    [[[XCTestBootstrapError describe:@"Failed to fetch test runner's path on device"]
      causedBy:innerError]
     fail:error];
  }

  // Get tested app document container path
  NSString *dataContainterDirectory = [deviceOperator containerPathForApplicationWithBundleID:testRunner.bundleID error:&innerError];
  if (!dataContainterDirectory) {
    return
    [[[XCTestBootstrapError describe:@"Failed to fetch test runner's data container path"]
      causedBy:innerError]
     fail:error];
  }

  // Load XCTest bundle
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle = [[[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.testBundlePath]
                               withCodesignProvider:deviceOperator.codesignProvider]
    withSessionIdentifier:sessionIdentifier]
    buildWithError:&innerError];

  if (!testBundle) {
    return
    [[[XCTestBootstrapError describe:@"Failed to prepare test bundle"]
      causedBy:innerError]
     fail:error];
  }
  // Load tested app data package
  FBApplicationDataPackage *dataPackage = [[[[[[[[FBApplicationDataPackageBuilder builderWithFileManager:self.fileManager]
    withPackagePath:self.applicationDataPath]
    withTestBundle:testBundle]
    withCodesignProvider:deviceOperator.codesignProvider]
    withWorkingDirectory:self.workingDirectory]
    withPlatformDirectory:self.pathToXcodePlatformDir]
    withDeviceDataDirectory:dataContainterDirectory]
    buildWithError:&innerError];

  if (!dataPackage) {
    return
    [[[XCTestBootstrapError describe:@"Failed to prepare data package"]
      causedBy:innerError]
     fail:error];
  }

  // Inastall tested app data package
  if (![deviceOperator uploadApplicationDataAtPath:dataPackage.path bundleID:testRunner.bundleID error:&innerError]) {
    return
    [[[XCTestBootstrapError describe:@"Failed to upload data package to device"]
      causedBy:innerError]
     fail:error];
  }

  FBProductBundle *remoteIDEBundleInjectionFramework =
  [dataPackage.IDEBundleInjectionFramework copyLocatedInDirectory:dataPackage.bundlePathOnDevice];
  FBProductBundle *remoteTestRunner = [testRunner copyLocatedInDirectory:remotePath.stringByDeletingLastPathComponent];

  NSString *remoteTestConfigurationPath = [dataPackage.testConfiguration.path
    stringByReplacingOccurrencesOfString:dataPackage.bundlePath
    withString:dataPackage.bundlePathOnDevice];

  return [[[[[[[[FBTestRunnerConfigurationBuilder builder]
    withSessionIdentifer:dataPackage.testConfiguration.sessionIdentifier]
    withTestRunnerApplication:remoteTestRunner]
    withIDEBundleInjectionFramework:remoteIDEBundleInjectionFramework]
    withWebDriverAgentTestBundle:testBundle]
    withTestConfigurationPath:remoteTestConfigurationPath]
    withFrameworkSearchPath:dataPackage.bundlePathOnDevice]
    build];
}

@end
