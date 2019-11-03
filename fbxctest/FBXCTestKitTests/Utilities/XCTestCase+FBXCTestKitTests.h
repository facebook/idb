/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@class FBXCTestLogger;

/**
 A logger for tests.
 */
@interface XCTestCase (Logger)

/**
 A unique logger for tests
 */
- (FBXCTestLogger *)logger;

/**
 Some tests are flakier on travis, this is a temporary way of disabling them until they are improved.
 */
+ (BOOL)isRunningOnTravis;

@end

NS_ASSUME_NONNULL_END
