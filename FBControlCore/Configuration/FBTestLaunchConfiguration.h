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

/**
 A Value object with the information required to launch a XCTest.
 */
@interface FBTestLaunchConfiguration : NSObject <NSCopying, FBiOSTargetFuture, FBDebugDescribeable>

/**
 The Designated Initializer

 @param testBundlePath path to test bundle
 @return a new FBTestLaunchConfiguration Instance
 */
+ (instancetype)configurationWithTestBundlePath:(NSString *)testBundlePath;

/**
 Path to XCTest bundle used for testing
 */
@property (nonatomic, copy, readonly, nullable) NSString *testBundlePath;

/**
 Configuration used to launch test runner application.
 */
@property (nonatomic, copy, readonly, nullable) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;

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
 Adds application launch configuration

 @param applicationLaunchConfiguration added application launch configuration
 @return new test launch configuration with changes applied.
 */
- (instancetype)withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration;

/**
 Adds timeout.

 @param timeout timeout
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTimeout:(NSTimeInterval)timeout;

/**
 Adds test host path.

 @param testHostPath test host path
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestHostPath:(NSString *)testHostPath;

/**
 Determines whether should initialize for UITesting

 @param shouldInitializeUITesting sets whether should initialize UITesting when starting test
 @return new test launch configuration with changes applied.
 */
- (instancetype)withUITesting:(BOOL)shouldInitializeUITesting;

/**
 Determines whether should use xcodebuild to run the test

 @param shouldUseXcodebuild sets whether should use xcodebuild to run the test
 @return new test launch configuration with changes applied.
 */
- (instancetype)withXcodebuild:(BOOL)shouldUseXcodebuild;

/**
 Adds tests to skip.

 @param testsToSkip tests to skip. Format: "className/methodName"
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip;

/**
 Adds tests to run.

 @param testsToRun tests to run. Format: "className/methodName"
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun;

/**
 Adds path to the target application for UI tests.
 @param targetApplicationPath path to the target application
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTargetApplicationPath:(NSString *)targetApplicationPath;

/**
 Adds path to the target application for UI tests.
 @param targetApplicationBundleID bundle ID of to the target application
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTargetApplicationBundleID:(NSString *)targetApplicationBundleID;

/**
 Adds xcTestRunProperties. When launching tests those properties will
 be passed to xcodebuild. Some of them will be overwritten with other
 values specified in this config.

 @param xcTestRunProperties the dictionary with contents of xctestrun file
 @return new test launch configuration with changes applied.
 */
- (instancetype)withXCTestRunProperties:(NSDictionary<NSString *, id> *)xcTestRunProperties;

/**
 Adds path to where xcodebuild will save results.
 Will be passed to xcodebuild with the -resultBundlePath argument.

 @param resultBundlePath path to the result bundle
 @return new test launch configuration with changes applied.
 */
- (instancetype)withResultBundlePath:(NSString *)resultBundlePath;


/**
 If set xctest will report activity data

 @param reportActivities set to report activity data
 @return new test launch configuration with changes applied.
 */
- (instancetype)withReportActivities:(BOOL)reportActivities;

/**
 Coverage data will be collected and saved to this path

 @param coveragePath  path to save coverage data to
 @return new test launch configuration with changes applied.
 */
- (instancetype)withCoveragePath:(NSString *)coveragePath;

@end

NS_ASSUME_NONNULL_END
