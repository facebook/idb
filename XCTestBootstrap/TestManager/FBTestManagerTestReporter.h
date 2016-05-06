/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBTestManagerAPIMediator;


/**
 A Delegate for providing callbacks for Test Reporting progress.
 */
@protocol FBTestManagerTestReporter <NSObject>

/**
 Called when a Test Plan begins Executing.

 @param mediator the mediator starting the Test Plan.
 */
- (void)testManagerMediatorDidBeginExecutingTestPlan:(FBTestManagerAPIMediator *)mediator;

/**
 Called when a Test Suite starts.

 @param mediator the test mediator.
 @param testSuite the Test Suite.
 @param startTime the Suite Start time.
 */
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime;

/**
 Called when a Test Case has completed.

 @param mediator the test mediator.
 @param testClass the Test Class.
 @param method the Test Method.
 @param status the status of the test case.
 @param duration the duration of the test case.
 */
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)status duration:(NSNumber *)duration;

/**
 Called when a Test Case fails

 @param testClass the Test Class.
 @param method the Test Method.
 @param message the failure message.
 @param file the file name.
 @param line the line number.
 */
- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line;

/**
 Called when a Test Bundle is ready.

 @param mediator the test mediator.
 @param protocolVersion ???
 @param minimumVersion ???
 */
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion;

/**
 Called when a Test Bundle is ready.

 @param mediator the test mediator.
 @param testClass the Test Class.
 @param method the Test Method.
 */
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method;

/**
 Called when a Test Suite has Finished.

 @param mediator the test mediator.
 @param testSuite the Test Suite
 @param finishTime the Time at which the suite finished.
 @param runCount the Number of Tests that were run.
 @param failuresCount the Number of tests that failed.
 @param unexpectedFailureCount the Number of Unexpected failures.
 @param testDuration the time taken to complete the test suite.
 @param totalDuration ???
 */
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testSuite:(NSString *)testSuite didFinishAt:(NSString *)finishTime runCount:(NSNumber *)runCount withFailures:(NSNumber *)failuresCount unexpected:(NSNumber *)unexpectedFailureCount testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration;

/**
 Called when the Mediator finished it's 'Test Plan'.

 @param mediator the test mediator.
 */
- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator;

@end
