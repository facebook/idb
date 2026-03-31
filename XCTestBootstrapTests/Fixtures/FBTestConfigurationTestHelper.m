/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestConfigurationTestHelper.h"

#import <objc/runtime.h>

#import <XCTestBootstrap/XCTestBootstrap.h>
#import <XCTestPrivate/XCTCapabilities.h>
#import <XCTestPrivate/XCTestConfiguration.h>

@implementation FBTestConfigurationTestHelper

+ (id)createXCTestConfiguration
{
  return [objc_lookUpClass("XCTestConfiguration") new];
}

+ (FBTestConfiguration *)createTestConfigurationWithSessionIdentifier:(NSUUID *)sessionIdentifier
                                                           moduleName:(NSString *)moduleName
                                                       testBundlePath:(NSString *)testBundlePath
                                                                 path:(NSString *)path
                                                            uiTesting:(BOOL)uiTesting
                                                  xcTestConfiguration:(id)xcTestConfiguration
{
  return [FBTestConfiguration configurationWithSessionIdentifier:sessionIdentifier
                                                      moduleName:moduleName
                                                  testBundlePath:testBundlePath
                                                            path:path
                                                       uiTesting:uiTesting
                                             xcTestConfiguration:(XCTestConfiguration *)xcTestConfiguration];
}

+ (FBTestConfiguration *)createTestConfigurationByWritingToFileWithSessionIdentifier:(NSUUID *)sessionIdentifier
                                                                          moduleName:(NSString *)moduleName
                                                                      testBundlePath:(NSString *)testBundlePath
                                                                           uiTesting:(BOOL)uiTesting
                                                                          testsToRun:(NSSet<NSString *> *)testsToRun
                                                                         testsToSkip:(NSSet<NSString *> *)testsToSkip
                                                               targetApplicationPath:(NSString *)targetApplicationPath
                                                           targetApplicationBundleID:(NSString *)targetApplicationBundleID
                                                         testApplicationDependencies:(NSDictionary<NSString *, NSString *> *)testApplicationDependencies
                                                             automationFrameworkPath:(NSString *)automationFrameworkPath
                                                                    reportActivities:(BOOL)reportActivities
                                                                               error:(NSError * _Nullable * _Nullable)error
{
  return [FBTestConfiguration configurationByWritingToFileWithSessionIdentifier:sessionIdentifier
                                                                     moduleName:moduleName
                                                                 testBundlePath:testBundlePath
                                                                      uiTesting:uiTesting
                                                                     testsToRun:testsToRun
                                                                    testsToSkip:testsToSkip
                                                          targetApplicationPath:targetApplicationPath
                                                      targetApplicationBundleID:targetApplicationBundleID
                                                    testApplicationDependencies:testApplicationDependencies
                                                        automationFrameworkPath:automationFrameworkPath
                                                               reportActivities:reportActivities
                                                                          error:error];
}

+ (NSString *)productModuleName:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig productModuleName];
}

+ (NSURL *)testBundleURL:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig testBundleURL];
}

+ (BOOL)initializeForUITesting:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig initializeForUITesting];
}

+ (NSString *)targetApplicationPath:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig targetApplicationPath];
}

+ (NSString *)targetApplicationBundleID:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig targetApplicationBundleID];
}

+ (BOOL)reportActivities:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig reportActivities];
}

+ (BOOL)reportResultsToIDE:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig reportResultsToIDE];
}

+ (NSDictionary *)ideCapabilitiesDictionary:(id)xcTestConfig
{
  return [(XCTestConfiguration *)xcTestConfig IDECapabilities].capabilitiesDictionary;
}

@end
