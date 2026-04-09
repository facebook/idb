/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationLaunchConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;

/**
 A Value object with the information required to launch a XCTest.
 */
@interface FBTestLaunchConfiguration : NSObject <NSCopying>

/**
 The Designated Initializer
 */
- (instancetype)initWithTestBundle:(FBBundleDescriptor *)testBundle applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostBundle:(nullable FBBundleDescriptor *)testHostBundle timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting useXcodebuild:(BOOL)useXcodebuild testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationBundle:(nullable FBBundleDescriptor *)targetApplicationBundle xcTestRunProperties:(nullable NSDictionary *)xcTestRunProperties resultBundlePath:(nullable NSString *)resultBundlePath reportActivities:(BOOL)reportActivities coverageDirectoryPath:(nullable NSString *)coverageDirectoryPath enableContinuousCoverageCollection:(BOOL)enableContinuousCoverageCollection logDirectoryPath:(nullable NSString *)logDirectoryPath reportResultBundle:(BOOL)reportResultBundle;

/**
 XCTest bundle used for testing
 */
@property (nullable, nonatomic, readonly, retain) FBBundleDescriptor *testBundle;

/**
 Configuration used to launch test runner application.
 */
@property (nonatomic, readonly, copy) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;

/**
 Host app bundle.
 */
@property (nullable, nonatomic, readonly, copy) FBBundleDescriptor *testHostBundle;

/**
 Timeout for the Test Launch.
 */
@property (nonatomic, readonly, assign) NSTimeInterval timeout;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, readonly, assign) BOOL shouldInitializeUITesting;

/**
 Determines whether should use xcodebuild to run the test
 */
@property (nonatomic, readonly, assign) BOOL shouldUseXcodebuild;

/*
 Run only these tests. Format: "className/methodName"
 */
@property (nullable, nonatomic, readonly, copy) NSSet<NSString *> *testsToRun;

/*
 Skip these tests. Format: "className/methodName"
 */
@property (nullable, nonatomic, readonly, copy) NSSet<NSString *> *testsToSkip;

/*
 Bundle of the target application for UI tests
 */
@property (nullable, nonatomic, readonly, strong) FBBundleDescriptor *targetApplicationBundle;

/*
 A dictionary with xctestrun file contents to use.
 */
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id> *xcTestRunProperties;

/*
 Path to the result bundle.
 */
@property (nullable, nonatomic, readonly, copy) NSString *resultBundlePath;

/**
 Determines whether xctest should report activity data
 */
@property (nonatomic, readonly, assign) BOOL reportActivities;

/**
 Path to coverage file
 */
@property (nullable, nonatomic, readonly, copy) NSString *coverageDirectoryPath;

/**
 Determines whether should enable continuous coverage collection
 */
@property (nonatomic, readonly, assign) BOOL shouldEnableContinuousCoverageCollection;

/**
 The Directory to use for storing logs generated during the execution of the test run.
 */
@property (nullable, nonatomic, readonly, copy) NSString *logDirectoryPath;

/*
 Path to the result bundle.
 */
@property (nonatomic, readonly, assign) BOOL reportResultBundle;

@end

NS_ASSUME_NONNULL_END
