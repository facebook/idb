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

@interface FBDeviceTestPreparationStrategy ()
@property (nonatomic, copy) NSString *applicationPath;
@property (nonatomic, copy) NSString *applicationDataPath;
@property (nonatomic, copy) NSString *testBundlePath;
@property (nonatomic, strong) id<FBFileManager> fileManager;
@end

@implementation FBDeviceTestPreparationStrategy

+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                        applicationDataPath:(NSString *)applicationDataPath
                             testBundlePath:(NSString *)testBundlePath
{
  return
  [self strategyWithApplicationPath:applicationPath
                applicationDataPath:applicationDataPath
                     testBundlePath:testBundlePath
                        fileManager:[NSFileManager defaultManager]];
}

+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                        applicationDataPath:(NSString *)applicationDataPath
                             testBundlePath:(NSString *)testBundlePath
                                fileManager:(id<FBFileManager>)fileManager
{
  FBDeviceTestPreparationStrategy *strategy = [self.class new];
  strategy.applicationPath = applicationPath;
  strategy.applicationDataPath = applicationDataPath;
  strategy.testBundlePath = testBundlePath;
  strategy.fileManager = fileManager;
  return strategy;
}

- (FBTestRunnerConfiguration *)prepareTestWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator error:(NSError **)error
{
  NSAssert(deviceOperator, @"deviceOperator is needed to load bundles");
  NSAssert(self.applicationPath, @"Path to application is needed to load bundles");
  NSAssert(self.applicationDataPath, @"Path to application data bundle is needed to prepare bundles");
  NSAssert(self.testBundlePath, @"Path to test bundle is needed to load bundles");

  // Load tested application
  FBProductBundle *testRunner =
  [[[FBProductBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.applicationPath]
   build];

  if (![deviceOperator isApplicationInstalledWithBundleID:testRunner.bundleID error:error]) {
    if (![deviceOperator installApplicationWithPath:testRunner.path error:error]) {
      return nil;
    }
  }

  // Get tested app path on device
  NSString *remotePath = [deviceOperator applicationPathForApplicationWithBundleID:testRunner.bundleID error:error];
  if (!remotePath) {
    return nil;
  }

  // Get tested app document container path
  NSString *dataContainterDirectory = [deviceOperator containerPathForApplicationWithBundleID:testRunner.bundleID error:error];
  if (!dataContainterDirectory) {
    return nil;
  }

  // Load XCTest bundle
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle = [[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.testBundlePath]
    withSessionIdentifier:sessionIdentifier]
    build];

  // Load tested app data package
  FBApplicationDataPackage *dataPackage = [[[[[FBApplicationDataPackageBuilder builderWithFileManager:self.fileManager]
    withPackagePath:self.applicationDataPath]
    withTestBundle:testBundle]
    withDeviceDataDirectory:dataContainterDirectory]
    build];

  // Inastall tested app data package
  if (![deviceOperator uploadApplicationDataAtPath:dataPackage.path bundleID:testRunner.bundleID error:error]) {
    return nil;
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
