/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBTestConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 Helper for FBTestConfigurationTests that wraps XCTestConfiguration interactions.
 This is needed because XCTestPrivate cannot be imported from Swift due to module
 conflicts with the system XCTest framework.
 */
@interface FBTestConfigurationTestHelper : NSObject

+ (id)createXCTestConfiguration;

+ (FBTestConfiguration *)createTestConfigurationWithSessionIdentifier:(NSUUID *)sessionIdentifier
                                                           moduleName:(NSString *)moduleName
                                                       testBundlePath:(NSString *)testBundlePath
                                                                 path:(NSString *)path
                                                            uiTesting:(BOOL)uiTesting
                                                  xcTestConfiguration:(id)xcTestConfiguration;

+ (nullable FBTestConfiguration *)createTestConfigurationByWritingToFileWithSessionIdentifier:(NSUUID *)sessionIdentifier
                                                                                   moduleName:(NSString *)moduleName
                                                                               testBundlePath:(NSString *)testBundlePath
                                                                                    uiTesting:(BOOL)uiTesting
                                                                                   testsToRun:(nullable NSSet<NSString *> *)testsToRun
                                                                                  testsToSkip:(nullable NSSet<NSString *> *)testsToSkip
                                                                        targetApplicationPath:(nullable NSString *)targetApplicationPath
                                                                    targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID
                                                                  testApplicationDependencies:(nullable NSDictionary<NSString *, NSString *> *)testApplicationDependencies
                                                                      automationFrameworkPath:(nullable NSString *)automationFrameworkPath
                                                                             reportActivities:(BOOL)reportActivities
                                                                                        error:(NSError **)error;

+ (nullable NSString *)productModuleName:(id)xcTestConfig;
+ (nullable NSURL *)testBundleURL:(id)xcTestConfig;
+ (BOOL)initializeForUITesting:(id)xcTestConfig;
+ (nullable NSString *)targetApplicationPath:(id)xcTestConfig;
+ (nullable NSString *)targetApplicationBundleID:(id)xcTestConfig;
+ (BOOL)reportActivities:(id)xcTestConfig;
+ (BOOL)reportResultsToIDE:(id)xcTestConfig;
+ (nullable NSDictionary *)ideCapabilitiesDictionary:(id)xcTestConfig;

@end

NS_ASSUME_NONNULL_END
