/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBActivityRecord;
@class FBTestManagerAPIMediator;
@class FBTestManagerResultSummary;

/**
 An Enumerated Type for Test Report Results.
 */
typedef NS_ENUM(NSUInteger, FBTestReportStatus) {
  FBTestReportStatusUnknown = 0,
  FBTestReportStatusPassed = 1,
  FBTestReportStatusFailed = 2
};

/**
 A Delegate for providing callbacks for Test Reporting progress.
 */
@protocol FBTestManagerTestReporter <NSObject>

/**
 Called when a Test Plan begins Executing.

 @param mediator the mediator starting the Test Plan.
 */
- (void)testManagerMediatorDidBeginExecutingTestPlan:(nullable FBTestManagerAPIMediator *)mediator;

/**
 Called when a Test Suite starts.

 @param mediator the test mediator.
 @param testSuite the Test Suite.
 @param startTime the Suite Start time.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime;

/**
 Called when a Test Case has completed.

 @param mediator the test mediator.
 @param testClass the Test Class.
 @param method the Test Method.
 @param status the status of the test case.
 @param duration the duration of the test case.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration;

/**
 Called when a Test Case fails

 @param testClass the Test Class.
 @param method the Test Method.
 @param message the failure message.
 @param file the file name.
 @param line the line number.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(nullable NSString *)file line:(NSUInteger)line;

/**
 Called when a Test Bundle is ready.

 @param mediator the test mediator.
 @param protocolVersion ???
 @param minimumVersion ???
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testBundleReadyWithProtocolVersion:(NSInteger)protocolVersion minimumVersion:(NSInteger)minimumVersion;

/**
 Called when a Test Bundle is ready.

 @param mediator the test mediator.
 @param testClass the Test Class.
 @param method the Test Method.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method;

/**
 Called when a Test Suite has Finished.

 @param mediator the test mediator.
 @param summary the Test Result Summary.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator finishedWithSummary:(FBTestManagerResultSummary *)summary;

/**
 Called when the Mediator finished it's 'Test Plan'.

 @param mediator the test mediator.
 */
- (void)testManagerMediatorDidFinishExecutingTestPlan:(nullable FBTestManagerAPIMediator *)mediator;

@optional
/**
 Called when the app under test has exited
 */
- (void)appUnderTestExited;

/**
 Called when a activity has started

 @param mediator the test mediator
 @param testClass the current test class
 @param method the current test method
 @param activity information about the activity
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator  testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity;

/**
 Called when a activity has finished

 @param mediator the test mediator
 @param testClass the current test class
 @param method the current test method
 @param activity information about the activity
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator  testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity;

/**
 Called when a Test Case has completed.

 @note This will be called instead of testManagerMediator:testCaseDidFinishForTestClass:method:withStatus:duration:logs: if implemented
 @param mediator the test mediator.
 @param testClass the Test Class.
 @param method the Test Method.
 @param status the status of the test case.
 @param duration the duration of the test case.
 @param logs the logs for the test case.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(nullable NSArray *)logs;

/**
 Called when the test plan fails for some global issue not specific to any one test

 @param message the failure message.
 */
- (void)testManagerMediator:(nullable FBTestManagerAPIMediator *)mediator testPlanDidFailWithMessage:(nonnull NSString *) message;

@end

NS_ASSUME_NONNULL_END
