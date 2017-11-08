/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A common protocol for types of test execution.
 */
@protocol FBXCTestRunner <NSObject>

/**
 Executes the Tests.

 @return a Future that resolves when the test has finished.
 */
- (FBFuture<NSNull *> *)execute;

@end

NS_ASSUME_NONNULL_END
