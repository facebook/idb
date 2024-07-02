/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBCodeCoverageConfiguration;
@class FBTestLaunchConfiguration;


NS_ASSUME_NONNULL_BEGIN

/**
 Wrap around FBTestLaunchConfiguration and FBCodeCoverageConfiguration for App and UI tests
 */
@interface FBIDBAppHostedTestConfiguration : NSObject

@property(nonatomic, strong, retain, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;

@property(nonatomic, strong, retain, nullable, readonly) FBCodeCoverageConfiguration *coverageConfiguration;

- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfig;

@end

NS_ASSUME_NONNULL_END
