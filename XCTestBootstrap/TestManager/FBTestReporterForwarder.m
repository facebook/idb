/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestReporterForwarder.h"

#import <XCTest/XCTestManager_IDEInterface-Protocol.h>
#import <XCTest/XCActivityRecord.h>

#import "FBActivityRecord.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerResultSummary.h"
#import "FBXCTestReporter.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestReporterForwarder () <XCTestManager_IDEInterface>

@property (nonatomic, weak, readonly) FBTestManagerAPIMediator<XCTestManager_IDEInterface> *mediator;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

@end

@implementation FBTestReporterForwarder

+ (instancetype)withAPIMediator:(FBTestManagerAPIMediator<XCTestManager_IDEInterface> *)mediator reporter:(id<FBXCTestReporter>)reporter;
{
  return [[self alloc] initWithAPIMediator:mediator reporter:reporter];
}

- (instancetype)initWithAPIMediator:(FBTestManagerAPIMediator<XCTestManager_IDEInterface> *)mediator reporter:(id<FBXCTestReporter>)reporter;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mediator = mediator;
  _reporter = reporter;

  return self;
}

#pragma mark Delegate Forwarding

- (BOOL)respondsToSelector:(SEL)selector
{
  return [super respondsToSelector:selector] || [self.mediator respondsToSelector:selector] || self.mediator == nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [(id)self.mediator methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.mediator respondsToSelector:invocation.selector] || self.mediator == nil) {
    [invocation invokeWithTarget:self.mediator];
  } else {
    [super forwardInvocation:invocation];
  }
}

#pragma mark Protocol Implementation

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  [self.reporter testSuite:tests didStartAt:time];
  return [self.mediator _XCT_testSuite:tests didStartAt:time];
}

- (id)_XCT_logDebugMessage:(NSString *)arg1
{
  return [self.mediator _XCT_logDebugMessage:arg1];
}

- (id)_XCT_didBeginExecutingTestPlan
{
  [self.reporter didBeginExecutingTestPlan];
  return [self.mediator _XCT_didBeginExecutingTestPlan];
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.reporter testCaseDidStartForTestClass:testClass method:method];
  return [self.mediator _XCT_testCaseDidStartForTestClass:testClass method:method];
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
  [self.reporter testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line.unsignedIntegerValue];
  return [self.mediator _XCT_testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line];
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
  return [self.mediator _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  FBTestReportStatus status = [FBTestManagerResultSummary statusForStatusString:statusString];
  [self.reporter testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration.doubleValue logs:@[]];
  return [self.mediator _XCT_testCaseDidFinishForTestClass:testClass method:method withStatus:statusString duration:duration];
}

- (id)_XCT_testSuite:(NSString *)testSuite didFinishAt:(NSString *)time runCount:(NSNumber *)runCount withFailures:(NSNumber *)failures unexpected:(NSNumber *)unexpected testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration
{
  FBTestManagerResultSummary *summary = [FBTestManagerResultSummary fromTestSuite:testSuite finishingAt:time runCount:runCount failures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
  [self.reporter finishedWithSummary:summary];
  return [self.mediator _XCT_testSuite:testSuite didFinishAt:time runCount:runCount withFailures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
}

- (id)_XCT_testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(XCActivityRecord *)activity
{
  FBActivityRecord *wrapped = [FBActivityRecord from:activity];
  if ([self.reporter respondsToSelector:@selector(testCase:method:didFinishActivity:)]) {
    [self.reporter testCase:testClass method:method didFinishActivity:wrapped];
  }
  return [self.mediator _XCT_testCase:testClass method:method didFinishActivity:activity];
}

- (id)_XCT_testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(XCActivityRecord *)activity
{
  FBActivityRecord *wrapped = [FBActivityRecord from:activity];
  if ([self.reporter respondsToSelector:@selector(testCase:method:willStartActivity:)]) {
    [self.reporter testCase:testClass method:method willStartActivity:wrapped];
  }
  return [self.mediator _XCT_testCase:testClass method:method willStartActivity:activity];
}

@end

#pragma clang diagnostic pop
