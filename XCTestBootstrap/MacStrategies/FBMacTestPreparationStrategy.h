/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>

@class FBCodesignProvider;
@class FBTestLaunchConfiguration;
@class FBXCTestShimConfiguration;

/**
 Strategy used to run XCTest with MacOSX.
 It will copy the Test Bundle to a working directory and update with an appropriate xctestconfiguration.
 */

@interface FBMacTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

@end
