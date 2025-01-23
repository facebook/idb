/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBCodeCoverageRequest;
@class FBIDBTestOperation;
@class FBTemporaryDirectory;
@class FBXCTestBundleStorage;

NS_ASSUME_NONNULL_BEGIN

/**
 Describes the necessary information to start a test run.
 */
@interface FBXCTestRunRequest : NSObject

#pragma mark Initializers

/**
 The Initializer for Logic Tests.

 @param testBundleID the bundle id of the test to run.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @param waitForDebugger a boolean describing whether the tests should stop after Run and wait for a debugger to be attached.
 @return an FBXCTestRunRequest instance.
 */
+ (instancetype)logicTestWithTestBundleID:(NSString *)testBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle;

/**
 Initializer for Logic Tests from a test path.

 @param testPath the path of the .xctest or .xctestrun file.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @param waitForDebugger a boolean describing whether the tests should stop after Run and wait for a debugger to be attached.
 @return an FBXCTestRunRequest instance.
 */
+ (instancetype)logicTestWithTestPath:(NSURL *)testPath environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle;

/**
The Initializer for App Tests.

 @param testBundleID the bundle id of the test to run.
 @param testHostAppBundleID the bundle id of the application to inject the test bundle into.
 @param environment environment for the application test process.
 @param arguments arguments for the application test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)applicationTestWithTestBundleID:(NSString *)testBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle;


/**
The Initializer for App Tests from a test path.

 @param testPath the path of the .xctest or .xctestrun file.
 @param testHostAppBundleID the bundle id of the application to inject the test bundle into.
 @param environment environment for the application test process.
 @param arguments arguments for the application test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)applicationTestWithTestPath:(NSURL *)testPath testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs waitForDebugger:(BOOL)waitForDebugger collectResultBundle:(BOOL)collectResultBundle;

/**
The Initializer for UI Tests.

 @param testBundleID the bundle id of the test to run.
 @param testHostAppBundleID the bundle id of the application hosting the test bundle.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)uiTestWithTestBundleID:(NSString *)testBundleID testHostAppBundleID:(NSString *)testHostAppBundleID testTargetAppBundleID:(NSString *)testTargetAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs collectResultBundle:(BOOL)collectResultBundle;


/**
The Initializer for UI Tests.

 @param testPath the bundle id of the test to run.
 @param testHostAppBundleID the bundle id of the application hosting the test bundle.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param coverageRequest information about llvm code coverage collection
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)uiTestWithTestPath:(NSURL *)testPath testHostAppBundleID:(NSString *)testHostAppBundleID testTargetAppBundleID:(NSString *)testTargetAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities reportAttachments:(BOOL)reportAttachments coverageRequest:(FBCodeCoverageRequest *)coverageRequest collectLogs:(BOOL)collectLogs collectResultBundle:(BOOL)collectResultBundle;

#pragma mark Properties

/**
 YES if a logic test, NO otherwise
 */
@property (nonatomic, assign, readonly) BOOL isLogicTest;

/**
 YES if a UI Test, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL isUITest;

/**
 The Bundle ID of the Test bundle.
 */
@property (nonatomic, copy, readonly) NSString *testBundleID;

/**
 The path of the .xctest or .xctestrun file.
 */
 @property (nonatomic, copy, readonly) NSURL *testPath;

/**
 The Bundle ID of the Test Host, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testHostAppBundleID;

/**
 The Bundle ID of the Test Target (a.k.a. App Under Test), if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testTargetAppBundleID;

/**
 The environment variables for the application, if relevant
 */
@property (nonatomic, copy, nullable, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 The arguments for the application, if relevant
 */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *arguments;

/**
 The set of tests to run, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSSet<NSString *> *testsToRun;

/**
 The set of tests to skip, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSSet<NSString *> *testsToSkip;

/**
 The timeout of the entire execution, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *testTimeout;

/**
 If set activities and their data will be reported
 */
@property (nonatomic, assign, readonly) BOOL reportActivities;

/**
 Whether to report activities or not.
 */
@property (nonatomic, assign, readonly) BOOL reportAttachments;

/**
 If set llvm coverage data will be collected
 */
@property (nonatomic, retain, readonly) FBCodeCoverageRequest *coverageRequest;

/**
 If set tests' output logs will be collected
 */
@property (nonatomic, assign, readonly) BOOL collectLogs;

/**
 If set tests' would stop after Run and wait for a debugger to be attached.
 */
@property (nonatomic, assign, readonly) BOOL waitForDebugger;

/**
 If set tests' result bundle will be collected
 */
@property (nonatomic, assign, readonly) BOOL collectResultBundle;

/**
 Starts the test operation.

 @param bundleStorage the bundle storage class to use.
 @param target the target to run against.
 @param reporter the reporter to report test results to.
 @param logger the logger to log to.
 @param temporaryDirectory the temporary directory to use.
 @return a future that resolves when the test operation starts.
 */
- (FBFuture<FBIDBTestOperation *> *)startWithBundleStorageManager:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory;

@end

NS_ASSUME_NONNULL_END
