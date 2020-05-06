/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBTestManagerResultSummary.h>
#import <XCTestBootstrap/FBActivityRecord.h>
#import <XCTestBootstrap/FBAttachment.h>

NS_ASSUME_NONNULL_BEGIN

/**
 fbxtest's reporting protocol.
 */
@protocol FBXCTestReporter <NSObject>

/**
 Called when a process has been launched and is awaiting a debugger to be attached.

 @param pid the process identifer of the waiting process.
 */
- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid;

/**
 Called when a process has resumed after a debugger has been attached.
 */
- (void)debuggerAttached;

/**
 Called when the test plan has started executing.
 */
- (void)didBeginExecutingTestPlan;

/**
 Called when the test plan has finished executing.
 */
- (void)didFinishExecutingTestPlan;


/**
 Called when the app under test exists
 */
- (void)appUnderTestExited;

/**
 Called when the Test Suite has started.

 @param testSuite the started test suite
 @param startTime a string representation of the start time.
 */
- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime;

/**
 Called when a test case has finished

 @note This will be called instead of testCaseDidFinishForTestClass:method:withStatus:duration:logs: if implemented
 @param testClass the test class that has finished.
 @param method the test method that has finished.
 @param status the status of the finish of the test case.
 @param duration the duration of the test case.
 @param logs the logs from the test case.
 */
- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(nullable NSArray<NSString *> *)logs;

/**
 Called when a test case has failed.

 @param testClass the test class that has failed.
 @param method the test method that has failed.
 @param message the failure message.
 @param file the failing file.
 @param line the failing line number.
 */
- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line;

/**
 Called when a test case has started

 @param testClass the test class that has started.
 @param method the test method that has started.
 */
- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method;

/**
 Called to summarize the results of a test execution

 @param summary the test summary.
 */
- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary;

/**
 Called when the test process has some output.

 @param output the test output.
 */
- (void)testHadOutput:(NSString *)output;

/**
 Called for some external event to be relayed.

 @param event the encoded event.
 */
- (void)handleExternalEvent:(NSString *)event;

/**
 Called when the results of the test should be written to the output.

 @param error an error for an error that occurs.
 */
- (BOOL)printReportWithError:(NSError **)error;

@optional
/**
 Called when a activity has started

 @param testClass the current test class
 @param method the current test method
 @param activity information about the activity
 */
- (void)testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity;

/**
 Called when a activity has finished

 @param testClass the current test class
 @param method the current test method
 @param activity information about the activity
 */
- (void)testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity;

/**
 Called when the test plan fails for some global issue not specific to any one test

 @param message the failure message.
 */
- (void)testPlanDidFailWithMessage:(nonnull NSString *) message;

/**
 Called after finished a video recording during test run.

 @param videoRecordingPath the file path of video recording
 */
- (void)didRecordVideoAtPath:(nonnull NSString *)videoRecordingPath;

/**
 Called after saving os_log during test run.

 @param osLogPath the file path of os log
 */
- (void)didSaveOSLogAtPath:(nonnull NSString *)osLogPath;

/**
 Called after copy a test artifacts out of simulator's folder.

 @param testArtifactFilename the file name of the test artifacts.
 @param path the new path that the test artifact is copied to.
 */
- (void)didCopiedTestArtifact:(nonnull NSString *)testArtifactFilename toPath:(nonnull NSString *)path;

/**
 Called when the test process has crashed mid test

 @param error error returned by the test process, most likely includes a stack trace
 */
- (void)didCrashDuringTest:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
