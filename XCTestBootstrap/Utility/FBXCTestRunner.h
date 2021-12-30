/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

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
