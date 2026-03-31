/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTestConfiguration;

/**
 Represents XCTestConfiguration class used by Apple to configure tests (aka .xctestconfiguration)
 */
@interface FBTestConfiguration : NSObject

/**
 Creates a Test Configuration, writing it out to a file and returning the result.

 @param sessionIdentifier the session identifier.
 @param moduleName name the test module name.
 @param testBundlePath the absolute path to the test bundle.
 @param uiTesting YES if to initialize the Test Configuraiton for UI Testing, NO otherwise.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip.
 @param targetApplicationPath Target application path
 @param targetApplicationBundleID Target application bundle id
 @param testApplicationDependencies Dictionary with dependencies required to execute the tests
 @param automationFrameworkPath Path to automation framework
 @param reportActivities whether to report activities
 @param error an error out for any error that occurs.
 @return a test configuration after it has been written out to disk.
 */
+ (nullable instancetype)configurationByWritingToFileWithSessionIdentifier:(nonnull NSUUID *)sessionIdentifier moduleName:(nonnull NSString *)moduleName testBundlePath:(nonnull NSString *)testBundlePath uiTesting:(BOOL)uiTesting testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID testApplicationDependencies:(nullable NSDictionary<NSString *, NSString *> *)testApplicationDependencies automationFrameworkPath:(nullable NSString *)automationFrameworkPath reportActivities:(BOOL)reportActivities error:(NSError * _Nullable * _Nullable)error;

/**
 Creates a Test Configuration.

 @param sessionIdentifier the session identifier.
 @param moduleName name the test module name.
 @param testBundlePath the absolute path to the test bundle.
 @param uiTesting YES if to initialize the Test Configuraiton for UI Testing, NO otherwise.
 @param xcTestConfiguration underlying XCTestConfiguration object
 */
+ (nonnull instancetype)configurationWithSessionIdentifier:(nonnull NSUUID *)sessionIdentifier moduleName:(nonnull NSString *)moduleName testBundlePath:(nonnull NSString *)testBundlePath path:(nonnull NSString *)path uiTesting:(BOOL)uiTesting xcTestConfiguration:(nonnull XCTestConfiguration *)xcTestConfiguration;

/**
 The session identifier
 */
@property (nonnull, nonatomic, readonly, copy) NSUUID *sessionIdentifier;

/**
 The name of the test module
 */
@property (nonnull, nonatomic, readonly, copy) NSString *moduleName;

/**
 The path to test bundle
 */
@property (nonnull, nonatomic, readonly, copy) NSString *testBundlePath;

/**
 The path to test configuration
 */
@property (nonnull, nonatomic, readonly, copy) NSString *path;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, readonly, assign) BOOL shouldInitializeForUITesting;

@property (nonnull, nonatomic, readonly, strong) XCTestConfiguration *xcTestConfiguration;

@end
