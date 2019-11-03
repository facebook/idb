/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;
@class FBXCTestShimConfiguration;

@protocol FBFileManager;
@protocol FBCodesignProvider;

/**
 Strategy used to run XCTest with Simulators.
 It will copy the Test Bundle to a working directory and update with an appropriate xctestconfiguration.
 */
@interface FBSimulatorTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

@end

NS_ASSUME_NONNULL_END
