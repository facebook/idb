/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTCapabilities, XCTExpectedFailure, XCTIssue, XCTSourceCodeContext, XCTTestIdentifier, XCTestCaseRunConfiguration;

@protocol XCTMessagingRole_TestReporting
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didStallOnMainThreadInFile:(NSString *)arg2 line:(NSNumber *)arg3;
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didFinishWithStatus:(NSString *)arg2 duration:(NSNumber *)arg3;
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didRecordExpectedFailure:(XCTExpectedFailure *)arg2;
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didRecordIssue:(XCTIssue *)arg2;
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 wasSkippedWithMessage:(NSString *)arg2 sourceCodeContext:(XCTSourceCodeContext *)arg3;
- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1 iteration:(NSNumber *)arg2;
- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1;
- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1 testCaseRunConfiguration:(XCTestCaseRunConfiguration *)arg2;
- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 skipCount:(NSNumber *)arg4 failureCount:(NSNumber *)arg5 expectedFailureCount:(NSNumber *)arg6 uncaughtExceptionCount:(NSNumber *)arg7 testDuration:(NSNumber *)arg8 totalDuration:(NSNumber *)arg9;
- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)arg1 didRecordIssue:(XCTIssue *)arg2;
- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)arg1 didStartAt:(NSString *)arg2;
- (id)_XCT_didFinishExecutingTestPlan;
- (id)_XCT_didBeginExecutingTestPlan;
- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)arg1 minimumVersion:(NSNumber *)arg2;
- (id)_XCT_testRunnerReadyWithCapabilities:(XCTCapabilities *)arg1;
- (id)_XCT_reportTestWithIdentifier:(XCTTestIdentifier *)arg1 didExceedExecutionTimeAllowance:(NSNumber *)arg2;
- (id)_XCT_didFailToBootstrapWithError:(NSError *)arg1;
@end
