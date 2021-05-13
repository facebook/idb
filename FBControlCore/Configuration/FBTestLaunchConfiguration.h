/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationLaunchConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBXCTestShimConfiguration;

/**
 A Value object with the information required to launch a XCTest.
 */
@interface FBTestLaunchConfiguration : NSObject <NSCopying>

/**
 The Designated Initializer
 */
- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostPath:(nullable NSString *)testHostPath timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting useXcodebuild:(BOOL)useXcodebuild testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicaitonBundleID xcTestRunProperties:(nullable NSDictionary *)xcTestRunProperties resultBundlePath:(nullable NSString *)resultBundlePath reportActivities:(BOOL)reportActivities coveragePath:(nullable NSString *)coveragePath logDirectoryPath:(nullable NSString *)logDirectoryPath shims:(nullable FBXCTestShimConfiguration *)shims;

/**
 Path to XCTest bundle used for testing
 */
@property (nonatomic, copy, readonly, nullable) NSString *testBundlePath;

/**
 Configuration used to launch test runner application.
 */
@property (nonatomic, copy, readonly) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;

/**
 Path to host app.
 */
@property (nonatomic, copy, readonly, nullable) NSString *testHostPath;

/**
 Timeout for the Test Launch.
 */
@property (nonatomic, assign, readonly) NSTimeInterval timeout;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, assign, readonly) BOOL shouldInitializeUITesting;

/**
 Determines whether should use xcodebuild to run the test
 */
@property (nonatomic, assign, readonly) BOOL shouldUseXcodebuild;

/*
 Run only these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly, nullable) NSSet<NSString *> *testsToRun;

/*
 Skip these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly, nullable) NSSet<NSString *> *testsToSkip;

/*
 Bundle ID of to the target application for UI tests
 */
@property (nonatomic, copy, readonly, nullable) NSString *targetApplicationBundleID;

/*
 Path to the target application for UI tests
 */
@property (nonatomic, copy, readonly, nullable) NSString *targetApplicationPath;

/*
 A dictionary with xctestrun file contents to use.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *xcTestRunProperties;

/*
 Path to the result bundle.
 */
@property (nonatomic, copy, readonly, nullable) NSString *resultBundlePath;

/**
 Determines whether xctest should report activity data
 */
@property (nonatomic, assign, readonly) BOOL reportActivities;

/**
 Path to coverage file
 */
@property (nonatomic, copy, readonly, nullable) NSString *coveragePath;

/**
 The Directory to use for storing logs generated during the execution of the test run.
 */
@property (nonatomic, nullable, copy, readonly) NSString *logDirectoryPath;

/**
 Shims to be applied to test execution
 */
@property (nonatomic, copy, readonly, nullable) FBXCTestShimConfiguration *shims;

@end

NS_ASSUME_NONNULL_END
