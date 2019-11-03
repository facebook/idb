/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestProcessExecutor.h>

NS_ASSUME_NONNULL_BEGIN

@class FBMacDevice;
@class FBXCTestShimConfiguration;

/**
 A Logic Test Strategy for macOS.
 */
@interface FBMacXCTestProcessExecutor : NSObject <FBXCTestProcessExecutor>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param macDevice the mac device instance.
 @param shims the shims to use.
 @return a new FBXCTestProcessExecutor.
 */
+ (instancetype)executorWithMacDevice:(FBMacDevice *)macDevice shims:(FBXCTestShimConfiguration *)shims;

@end

NS_ASSUME_NONNULL_END
