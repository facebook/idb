// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBTestManagerResultSummary.h>

@protocol FBXCTestReporter <NSObject>

- (void)didBeginExecutingTestPlan;
- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime;
- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration;
- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line;
- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method;
- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary;
- (void)didFinishExecutingTestPlan;

- (BOOL)printReportWithError:(NSError **)error;

@end
