/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreLoggerDouble.h"

#pragma mark - Expose Private Properties for Testing

@interface FBCrashLogNotifier (Testing)

@property (nonatomic, copy, readwrite) NSDate *sinceDate;

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

@end

#pragma mark - Test Class

@interface FBCrashLogNotifierTests : XCTestCase

@end

@implementation FBCrashLogNotifierTests

#pragma mark - startListening

- (void)testStartListening_WithOnlyNewYES_SetsSinceDateToNow
{
  FBControlCoreLoggerDouble *logger = [FBControlCoreLoggerDouble new];
  FBCrashLogNotifier *notifier = [[FBCrashLogNotifier alloc] initWithLogger:logger];

  // Set sinceDate to distant past first to verify it changes
  notifier.sinceDate = [NSDate distantPast];

  NSDate *before = [NSDate date];
  [notifier startListening:YES];
  NSDate *after = [NSDate date];

  NSDate *sinceDate = notifier.sinceDate;
  XCTAssertGreaterThanOrEqual(
      [sinceDate timeIntervalSinceReferenceDate],
      [before timeIntervalSinceReferenceDate],
      @"sinceDate should be updated to approximately now when onlyNew is YES");
  XCTAssertLessThanOrEqual(
      [sinceDate timeIntervalSinceReferenceDate],
      [after timeIntervalSinceReferenceDate],
      @"sinceDate should not be in the future");
}

- (void)testStartListening_WithOnlyNewNO_SetsSinceDateToDistantPast
{
  FBControlCoreLoggerDouble *logger = [FBControlCoreLoggerDouble new];
  FBCrashLogNotifier *notifier = [[FBCrashLogNotifier alloc] initWithLogger:logger];

  [notifier startListening:NO];

  XCTAssertEqualObjects(
      notifier.sinceDate,
      [NSDate distantPast],
      @"sinceDate should be set to distantPast when onlyNew is NO");
}

#pragma mark - nextCrashLogForPredicate

- (void)testNextCrashLogForPredicate_WhenNoMatchingCrashLog_FutureDoesNotResolveWithResult
{
  FBControlCoreLoggerDouble *logger = [FBControlCoreLoggerDouble new];
  FBCrashLogNotifier *notifier = [[FBCrashLogNotifier alloc] initWithLogger:logger];

  // Use a predicate that will never match any crash log
  NSPredicate *predicate = [NSPredicate predicateWithValue:NO];
  FBFuture<FBCrashLogInfo *> *future = [notifier nextCrashLogForPredicate:predicate];

  // The future should not resolve with a result since no crash log matches
  NSError *error = nil;
  id result = [future awaitWithTimeout:0.2 error:&error];

  XCTAssertNil(result, @"Future should not resolve with a result when no crash log matches the predicate");
  XCTAssertNotNil(error, @"Future should produce an error (timeout) when no crash log matches");
}

@end
