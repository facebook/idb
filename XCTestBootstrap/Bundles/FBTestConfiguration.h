/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileManager;

/**
 Represents XCTestConfiguration class used by Apple to configure tests (aka .xctestconfiguration)
 */
@interface FBTestConfiguration : NSObject

/**
 Creates a Test Configuration.

 @param fileManager the file manager to use.
 @param sessionIdentifier the session identifier.
 @param moduleName name the test module name.
 @param testBundlePath the full path to the test bundle.
 @param uiTesting YES if to initialize the Test Configuraiton for UI Testing, NO otherwise.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip.
 @param targetApplicationPath Target application path
 @param targetApplicationBundleID Target application bundle id
 @param automationFrameworkPath Path to automation framework
 @param savePath the path to save the configuration to.
 @param reportActivities whether to report activities
 @param error an error out for any error that occurs.
 */
+ (nullable instancetype)configurationWithFileManager:(id<FBFileManager>)fileManager sessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath uiTesting:(BOOL)uiTesting testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID automationFrameworkPath:(nullable NSString *)automationFrameworkPath savePath:(NSString *)savePath reportActivities:(BOOL)reportActivities error:(NSError **)error;

/**
 Creates a Test Configuration.

 @param sessionIdentifier the session identifier.
 @param moduleName name the test module name.
 @param testBundlePath the full path to the test bundle.
 @param uiTesting YES if to initialize the Test Configuraiton for UI Testing, NO otherwise.
 */
+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting;

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
@property (nonatomic, copy, readonly) NSString *path;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, assign, readonly) BOOL shouldInitializeForUITesting;

/**
 The path to automation framework
 */
@property (nonatomic, copy, readonly, nullable) NSString *automationFramework;

@end

NS_ASSUME_NONNULL_END
