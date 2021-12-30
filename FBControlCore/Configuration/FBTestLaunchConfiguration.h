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
- (instancetype)initWithTestBundle:(FBBundleDescriptor *)testBundle applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostBundle:(nullable FBBundleDescriptor *)testHostBundle timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting useXcodebuild:(BOOL)useXcodebuild testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip  targetApplicationBundle:(nullable FBBundleDescriptor *)targetApplicationBundle xcTestRunProperties:(nullable NSDictionary *)xcTestRunProperties resultBundlePath:(nullable NSString *)resultBundlePath reportActivities:(BOOL)reportActivities coverageDirectoryPath:(nullable NSString *)coverageDirectoryPath logDirectoryPath:(nullable NSString *)logDirectoryPath;

/**
 XCTest bundle used for testing
 */
@property (nonatomic, retain, readonly, nullable) FBBundleDescriptor *testBundle;

/**
 Configuration used to launch test runner application.
 */
@property (nonatomic, copy, readonly) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;

/**
 Host app bundle.
 */
@property (nonatomic, copy, readonly, nullable) FBBundleDescriptor *testHostBundle;

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
 Bundle of the target application for UI tests
 */
@property (nonatomic, strong, readonly, nullable) FBBundleDescriptor *targetApplicationBundle;

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
@property (nonatomic, copy, readonly, nullable) NSString *coverageDirectoryPath;

/**
 The Directory to use for storing logs generated during the execution of the test run.
 */
@property (nonatomic, nullable, copy, readonly) NSString *logDirectoryPath;

@end

NS_ASSUME_NONNULL_END
