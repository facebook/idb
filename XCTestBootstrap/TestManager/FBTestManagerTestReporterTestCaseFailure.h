/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Test Reporter Test Case Failure.
 */
@interface FBTestManagerTestReporterTestCaseFailure : NSObject

/**
 Constructs a Test Reporter Test Case Failure.

 @param message the failure message.
 @param file the file in which the test case failure happened.
 @param line the line number where the test case failure happened.
 @return a new test case failure instance.
 */
+ (instancetype)withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line;

/**
 The file in which the test case failure happened.
 */
@property (nonatomic, copy, readonly) NSString *file;

/**
 The failure message.
 */
@property (nonatomic, copy, readonly) NSString *message;

/**
 The line number where the test case failure happened.
 */
@property (nonatomic, readonly) NSUInteger line;

@end

NS_ASSUME_NONNULL_END
