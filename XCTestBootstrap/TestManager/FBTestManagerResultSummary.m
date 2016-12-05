/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerResultSummary.h"

@implementation FBTestManagerResultSummary

+ (instancetype)fromTestSuite:(NSString *)testSuite finishingAt:(NSString *)finishTime runCount:(NSNumber *)runCount failures:(NSNumber *)failuresCount unexpected:(NSNumber *)unexpectedFailureCount testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration
{
  NSParameterAssert(testSuite);
  NSParameterAssert(finishTime);
  NSParameterAssert(runCount);
  NSParameterAssert(failuresCount);
  NSParameterAssert(unexpectedFailureCount);
  NSParameterAssert(testDuration);
  NSParameterAssert(totalDuration);

  return [[FBTestManagerResultSummary alloc]
    initWithTestSuite:testSuite
    finishTime:[[self dateFormatter] dateFromString:finishTime]
    runCount:runCount.integerValue
    failureCount:failuresCount.integerValue
    unexpected:unexpectedFailureCount.integerValue
    testDuration:testDuration.doubleValue
    totalDuration:totalDuration.doubleValue];
}

- (instancetype)initWithTestSuite:(NSString *)testSuite finishTime:(NSDate *)finishTime runCount:(NSInteger)runCount failureCount:(NSInteger)failureCount unexpected:(NSInteger)unexpected testDuration:(NSTimeInterval)testDuration totalDuration:(NSTimeInterval)totalDuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testSuite = testSuite;
  _finishTime = finishTime;
  _runCount = runCount;
  _failureCount = failureCount;
  _unexpected = unexpected;
  _testDuration = testDuration;
  _totalDuration = totalDuration;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Suite %@ | Finish Time %@ | Run Count %lu | Failures %lu | Unexpected %lu | Test Duration %f | Total Duration %f",
    self.testSuite,
    self.finishTime,
    self.runCount,
    self.failureCount,
    self.unexpected,
    self.testDuration,
    self.totalDuration
  ];
}

+ (FBTestReportStatus)statusForStatusString:(NSString *)statusString
{
  if ([statusString isEqualToString:@"passed"]) {
    return FBTestReportStatusPassed;
  } else if ([statusString isEqualToString:@"failed"]) {
    return FBTestReportStatusFailed;
  }
  return FBTestReportStatusUnknown;
}

+ (NSString *)statusStringForStatus:(FBTestReportStatus)status
{
  switch (status) {
  case FBTestReportStatusUnknown:
    return @"Unknown";
  case FBTestReportStatusPassed:
    return @"Passed";
  case FBTestReportStatusFailed:
    return @"Failed";
  }
}

+ (NSDateFormatter *)dateFormatter
{
  NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
  dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
  dateFormatter.lenient = YES;
  return dateFormatter;
}


@end
