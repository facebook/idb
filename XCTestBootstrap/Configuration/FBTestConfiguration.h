/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTestConfiguration;

NS_ASSUME_NONNULL_BEGIN

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
+ (nullable instancetype)configurationByWritingToFileWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath uiTesting:(BOOL)uiTesting testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID testApplicationDependencies:(nullable NSDictionary<NSString *, NSString*> *)testApplicationDependencies automationFrameworkPath:(nullable NSString *)automationFrameworkPath reportActivities:(BOOL)reportActivities error:(NSError **)error;

/**
 Creates a Test Configuration.

 @param sessionIdentifier the session identifier.
 @param moduleName name the test module name.
 @param testBundlePath the absolute path to the test bundle.
 @param uiTesting YES if to initialize the Test Configuraiton for UI Testing, NO otherwise.
 @param xcTestConfiguration underlying XCTestConfiguration object
 */
+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting xcTestConfiguration:(XCTestConfiguration *)xcTestConfiguration;

/**
 The session identifier
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 The name of the test module
 */
@property (nonatomic, copy, readonly) NSString *moduleName;

/**
 The path to test bundle
 */
@property (nonatomic, copy, readonly) NSString *testBundlePath;

/**
 The path to test configuration, if saved
 */
@property (nonatomic, copy, readonly, nullable) NSString *path;

/**
 The path to automation framework
 */
@property (nonatomic, copy, readonly, nullable) NSString *automationFramework;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, assign, readonly) BOOL shouldInitializeForUITesting;

@property (nonatomic, strong, readonly) XCTestConfiguration *xcTestConfiguration;

@end

NS_ASSUME_NONNULL_END
