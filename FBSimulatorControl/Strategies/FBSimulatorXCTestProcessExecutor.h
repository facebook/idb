/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 An Executor of XCTest Processes for Simulators.
 */
@interface FBSimulatorXCTestProcessExecutor : NSObject <FBXCTestProcessExecutor>

#pragma mark Initializer

/**
 The Designated Initializer

 @param simulator the simulator.
 @param shims the shims to use.
 @return a new Logic Test Strategy for Simulators.
 */
+ (instancetype)executorWithSimulator:(FBSimulator *)simulator shims:(FBXCTestShimConfiguration *)shims;

@end

NS_ASSUME_NONNULL_END
