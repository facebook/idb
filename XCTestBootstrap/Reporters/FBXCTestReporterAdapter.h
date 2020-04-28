/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestBootstrap/FBTestManagerTestReporter.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBXCTestReporter;

/**
 An implementation of FBTestManagerTestReporter that delegates to a FBXCTestReporter.
 FBTestManagerTestReporter is only used inside mediated test runs via testmanagerd.
 FBXCTestReporter is the top-level reporter for every kind of Test Execution.
 This allows adapting to this base protocol for reporting
 */
@interface FBXCTestReporterAdapter : NSObject <FBTestManagerTestReporter>

/**
 The Designated Initializer.

 @param reporter the FBXCTestReporter to delegate to.
 @return an implementation of FBTestManagerTestReporter.
 */
+ (instancetype)adapterWithReporter:(id<FBXCTestReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
