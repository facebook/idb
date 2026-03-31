/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBTestConfiguration;

/**
 Helper for FBTestConfigurationTests that wraps XCTestConfiguration interactions.
 This is needed because XCTestPrivate cannot be imported from Swift due to module
 conflicts with the system XCTest framework.
 */
@interface FBTestConfigurationTestHelper : NSObject

+ (nonnull id)createXCTestConfiguration;

+ (nonnull FBTestConfiguration *)createTestConfigurationWithSessionIdentifier:(nonnull NSUUID *)sessionIdentifier
                                                                   moduleName:(nonnull NSString *)moduleName
                                                               testBundlePath:(nonnull NSString *)testBundlePath
                                                                         path:(nonnull NSString *)path
                                                                    uiTesting:(BOOL)uiTesting
                                                          xcTestConfiguration:(nonnull id)xcTestConfiguration;

+ (nullable FBTestConfiguration *)createTestConfigurationByWritingToFileWithSessionIdentifier:(nonnull NSUUID *)sessionIdentifier
                                                                                   moduleName:(nonnull NSString *)moduleName
                                                                               testBundlePath:(nonnull NSString *)testBundlePath
                                                                                    uiTesting:(BOOL)uiTesting
                                                                                   testsToRun:(nullable NSSet<NSString *> *)testsToRun
                                                                                  testsToSkip:(nullable NSSet<NSString *> *)testsToSkip
                                                                        targetApplicationPath:(nullable NSString *)targetApplicationPath
                                                                    targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID
                                                                  testApplicationDependencies:(nullable NSDictionary<NSString *, NSString *> *)testApplicationDependencies
                                                                      automationFrameworkPath:(nullable NSString *)automationFrameworkPath
                                                                             reportActivities:(BOOL)reportActivities
                                                                                        error:(NSError * _Nullable * _Nullable)error;

+ (nullable NSString *)productModuleName:(nonnull id)xcTestConfig;
+ (nullable NSURL *)testBundleURL:(nonnull id)xcTestConfig;
+ (BOOL)initializeForUITesting:(nonnull id)xcTestConfig;
+ (nullable NSString *)targetApplicationPath:(nonnull id)xcTestConfig;
+ (nullable NSString *)targetApplicationBundleID:(nonnull id)xcTestConfig;
+ (BOOL)reportActivities:(nonnull id)xcTestConfig;
+ (BOOL)reportResultsToIDE:(nonnull id)xcTestConfig;
+ (nullable NSDictionary *)ideCapabilitiesDictionary:(nonnull id)xcTestConfig;

@end
