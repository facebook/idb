/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 An Executor of XCTest Processes for Simulators.
 */
@interface FBSimulatorXCTestProcessExecutor : NSObject <FBXCTestProcessExecutor>

/**
 The Designated Initializer

 @param simulator the simulator.
 @param configuration the configuration.
 @return a new Logic Test Strategy for Simulators.
 */
+ (instancetype)executorWithSimulator:(FBSimulator *)simulator configuration:(FBXCTestConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
