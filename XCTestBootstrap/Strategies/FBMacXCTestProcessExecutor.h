/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
