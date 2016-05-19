/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestReporterForwarder.h"

#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerTestReporter.h"
#import "FBTestManagerResultSummary.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestReporterForwarder ()

@property (nonatomic, weak, readonly) FBTestManagerAPIMediator<XCTestManager_IDEInterface> *mediator;
@property (nonatomic, weak, readonly) id<FBTestManagerTestReporter> reporter;

@end

@implementation FBTestReporterForwarder

+ (instancetype)withAPIMediator:(FBTestManagerAPIMediator<XCTestManager_IDEInterface> *)mediator reporter:(id<FBTestManagerTestReporter>)reporter;
{
  return [[self alloc] initWithAPIMediator:mediator reporter:reporter];
}

- (instancetype)initWithAPIMediator:(FBTestManagerAPIMediator<XCTestManager_IDEInterface> *)mediator reporter:(id<FBTestManagerTestReporter>)reporter;
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
  return [super respondsToSelector:selector] || [self.mediator respondsToSelector:selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [(id)self.mediator methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.mediator respondsToSelector:invocation.selector]) {
    [invocation invokeWithTarget:self.mediator];
  } else {
    [super forwardInvocation:invocation];
  }
}

#pragma mark Protocol Implementation

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  [self.reporter testManagerMediator:self.mediator testSuite:tests didStartAt:time];
  return [self.mediator _XCT_testSuite:tests didStartAt:time];
}

- (id)_XCT_didBeginExecutingTestPlan
{
  [self.reporter testManagerMediatorDidBeginExecutingTestPlan:self.mediator];
  return [self.mediator _XCT_didBeginExecutingTestPlan];
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  [self.reporter testManagerMediator:self.mediator testBundleReadyWithProtocolVersion:protocolVersion.integerValue minimumVersion:minimumVersion.integerValue];
  return [self.mediator _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.reporter testManagerMediator:self.mediator testCaseDidStartForTestClass:testClass method:method];
  return [self.mediator _XCT_testCaseDidStartForTestClass:testClass method:method];
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
  [self.reporter testManagerMediator:self.mediator testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line.unsignedIntegerValue];
  return [self.mediator _XCT_testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line];
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.reporter testManagerMediatorDidFinishExecutingTestPlan:self.mediator];
  return [self.mediator _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  FBTestReportStatus status = [FBTestManagerResultSummary statusForStatusString:statusString];
  [self.reporter testManagerMediator:self.mediator testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration.integerValue];
  return [self.mediator _XCT_testCaseDidFinishForTestClass:testClass method:method withStatus:statusString duration:duration];
}

- (id)_XCT_testSuite:(NSString *)testSuite didFinishAt:(NSString *)time runCount:(NSNumber *)runCount withFailures:(NSNumber *)failures unexpected:(NSNumber *)unexpected testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration
{
  FBTestManagerResultSummary *summary = [FBTestManagerResultSummary fromTestSuite:testSuite finishingAt:time runCount:runCount failures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
  [self.reporter testManagerMediator:self.mediator finishedWithSummary:summary];
  return [self.mediator _XCT_testSuite:testSuite didFinishAt:time runCount:runCount withFailures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
}

@end

#pragma clang diagnostic pop
