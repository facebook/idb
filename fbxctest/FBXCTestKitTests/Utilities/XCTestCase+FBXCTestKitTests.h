/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
