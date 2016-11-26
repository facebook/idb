/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBApplicationLaunchConfiguration;
@protocol FBTestManagerTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object with the information required to launch a XCTest.
 */
@interface FBTestLaunchConfiguration : NSObject <NSCopying, FBJSONSerializable, FBDebugDescribeable>

/**
 The Designated Initializer

 @param testBundlePath path to test bundle
 @return a new FBTestLaunchConfiguration Instance
 */
+ (instancetype)configurationWithTestBundlePath:(NSString *)testBundlePath;

/**
 Path to XCTest bundle used for testing
 */
@property (nonatomic, copy, readonly) NSString *testBundlePath;

/*
 Path to the target application for UI tests
 */
@property (nonatomic, copy, readonly, nullable) NSString *targetApplicationPath;

/*
 Bundle ID of to the target application for UI tests
 */
@property (nonatomic, copy, readonly, nullable) NSString *targetApplicationBundleID;

/**
 Configuration used to launch test runner application.
 */
@property (nonatomic, copy, readonly, nullable) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;

/**
 Path to host app.
 */
@property (nonatomic, copy, readonly, nullable) NSString *testHostPath;

/**
 A Dictionary, mapping Strings to Strings of the Environment to set when the tests are launched.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSString *> *testEnvironment;

/**
 Timeout for the Test Launch.
 */
@property (nonatomic, assign, readonly) NSTimeInterval timeout;

/**
 Determines whether should initialize for UITesting
 */
@property (nonatomic, assign, readonly) BOOL shouldInitializeUITesting;

/*
 Skip these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *testsToSkip;

/*
 Run only these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *testsToRun;

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
 Adds test environment dictionary, mapping Strings to Strings of the Environment to
 set when the tests are launched.

 @param testEnvironment bundle ID of to the target application
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestEnvironment:(NSDictionary<NSString *, NSString *> *)testEnvironment;

/**
 Adds tests to skip.

 @param testsToSkip tests to skip
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip;

/**
 Adds tests to run.

 @param testsToRun tests to run
 @return new test launch configuration with changes applied.
 */
- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun;

@end

NS_ASSUME_NONNULL_END
