/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 An Enumerated Type for Test Report Results.
 */
typedef NS_ENUM(NSUInteger, FBTestReportStatus) {
  FBTestReportStatusUnknown = 0,
  FBTestReportStatusPassed = 1,
  FBTestReportStatusFailed = 2,
};

/**
 A Summary of Test Results.
 */
@interface FBTestManagerResultSummary : NSObject

/**
 Constructs a Result Summary from Test Delegate Arguments.
 */
+ (nonnull instancetype)fromTestSuite:(nonnull NSString *)testSuite finishingAt:(nonnull NSString *)finishTime runCount:(nonnull NSNumber *)runCount failures:(nonnull NSNumber *)failuresCount unexpected:(nonnull NSNumber *)unexpectedFailureCount testDuration:(nonnull NSNumber *)testDuration totalDuration:(nonnull NSNumber *)totalDuration;

/**
 Default initializer
 */
- (nonnull instancetype)initWithTestSuite:(nonnull NSString *)testSuite finishTime:(nonnull NSDate *)finishTime runCount:(NSInteger)runCount failureCount:(NSInteger)failureCount unexpected:(NSInteger)unexpected testDuration:(NSTimeInterval)testDuration totalDuration:(NSTimeInterval)totalDuration;

@property (nonnull, nonatomic, readonly, copy) NSString *testSuite;
@property (nonnull, nonatomic, readonly, copy) NSDate *finishTime;
@property (nonatomic, readonly, assign) NSInteger runCount;
@property (nonatomic, readonly, assign) NSInteger failureCount;
@property (nonatomic, readonly, assign) NSInteger unexpected;
@property (nonatomic, readonly, assign) NSTimeInterval testDuration;
@property (nonatomic, readonly, assign) NSTimeInterval totalDuration;

/**
 Returns a status enum value for the given status string.

 @param statusString the status string.
 @return the status enum value.
 */
+ (FBTestReportStatus)statusForStatusString:(nonnull NSString *)statusString;

/**
 Returns a status string for the given status enum value.

 @param status the status enum value.
 @return the status string.
*/
+ (nonnull NSString *)statusStringForStatus:(FBTestReportStatus)status;

@end
