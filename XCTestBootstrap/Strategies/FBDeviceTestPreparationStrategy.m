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

  // Load tested application
  FBProductBundle *testRunner =
  [[[[FBProductBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.applicationPath]
   withCodesignProvider:deviceOperator.codesignProvider]
   build];

  if (![deviceOperator isApplicationInstalledWithBundleID:testRunner.bundleID error:error]) {
    NSLog(@"[%@ %@] => %@ Test Runner app (%@) must be installed on device",
          NSStringFromClass(self.class),
          NSStringFromSelector(_cmd),
          nil,
          testRunner.bundleID);
      return nil;
  }

  // Get tested app path on device
  NSString *remotePath = [deviceOperator applicationPathForApplicationWithBundleID:testRunner.bundleID error:error];
  if (!remotePath) {
      NSLog(@"[%@ %@] => %@ (unable to get remote path for test runner bundle)",
            NSStringFromClass(self.class), NSStringFromSelector(_cmd), nil);
    return nil;
  }

  // Get tested app document container path
  NSString *dataContainterDirectory = [deviceOperator containerPathForApplicationWithBundleID:testRunner.bundleID error:error];
  if (!dataContainterDirectory) {
      NSLog(@"[%@ %@] => %@ (No data container directory)", NSStringFromClass(self.class), NSStringFromSelector(_cmd), nil);
    return nil;
  }

  // Load XCTest bundle
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle = [[[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.testBundlePath]
                               withCodesignProvider:deviceOperator.codesignProvider]
    withSessionIdentifier:sessionIdentifier]
                              
    build];
    NSString *platformDirectory = [self.pathToXcodePlatformDir stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform"];

  // Load tested app data package
  FBApplicationDataPackage *dataPackage = [[[[[[[[FBApplicationDataPackageBuilder builderWithFileManager:self.fileManager]
    withPackagePath:self.applicationDataPath]
    withTestBundle:testBundle]
    withCodesignProvider:deviceOperator.codesignProvider]
    withWorkingDirectory:self.workingDirectory]
    withPlatformDirectory:platformDirectory]
    withDeviceDataDirectory:dataContainterDirectory]
    build];

  // Inastall tested app data package
  if (![deviceOperator uploadApplicationDataAtPath:dataPackage.path
                                          bundleID:testRunner.bundleID
                                             error:error]) {
      NSLog(@"[%@ %@] => %@ (Unable to upload application data)",
            NSStringFromClass(self.class),
            NSStringFromSelector(_cmd),
            nil);
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
