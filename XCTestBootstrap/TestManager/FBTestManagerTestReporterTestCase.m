/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerTestReporterTestCase.h"

@interface FBTestManagerTestReporterTestCase ()

@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) FBTestReportStatus status;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *testClass;
@property (nonatomic, readonly) NSString *statusDescription;
@property (nonatomic, strong) NSMutableArray<FBTestManagerTestReporterTestCaseFailure *> *mutableFailures;

@end

@implementation FBTestManagerTestReporterTestCase

+ (instancetype)withTestClass:(NSString *)testClass method:(NSString *)method
{
  return [[self alloc] initWithTestClass:testClass method:method];
}

- (instancetype)initWithTestClass:(NSString *)testClass method:(NSString *)method
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testClass = [testClass copy];
  _method = [method copy];
  _mutableFailures = [NSMutableArray array];

  return self;
}

- (NSArray<FBTestManagerTestReporterTestCaseFailure *> *)failures
{
  return [self.mutableFailures copy];
}

- (void)addFailure:(FBTestManagerTestReporterTestCaseFailure *)failure
{
  [self.mutableFailures addObject:failure];
}

- (void)finishWithStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  NSAssert(!self.finished, @"finishWithStatus:duration: may be called only once");
  self.finished = YES;
  self.status = status;
  self.duration = duration;
}

#pragma mark -

- (NSString *)description
{
  return [NSString stringWithFormat:@"TestCase %@ | Method %@ | Status %@ | Duration %f", self.testClass, self.method,
                                    self.statusDescription, self.duration];
}

- (NSString *)statusDescription
{
  switch (self.status) {
  case FBTestReportStatusUnknown:
    return @"Unknown";
  case FBTestReportStatusPassed:
    return @"Passed";
  case FBTestReportStatusFailed:
    return @"Failed";
  }
}

@end
