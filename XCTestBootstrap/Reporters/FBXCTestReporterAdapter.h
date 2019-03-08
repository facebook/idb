/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestBootstrap/FBTestManagerTestReporter.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBXCTestReporter;

@interface FBXCTestReporterAdapter : NSObject <FBTestManagerTestReporter>

+ (instancetype)adapterWithReporter:(id<FBXCTestReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
